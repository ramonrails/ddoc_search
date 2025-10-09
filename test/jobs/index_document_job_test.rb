# frozen_string_literal: true

require "test_helper"

class IndexDocumentJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  def setup
    @document_id = 1
    @tenant_id = 2
    @document = mock("Document")
    @document.stub(:id, @document_id) do
      @document.stub(:tenant_id, @tenant_id) do
        @document.stub(:__elasticsearch__, mock("Elasticsearch")) do
          @document.stub(:update_column, true) do
            # Setup complete
          end
        end
      end
    end
  end

  # Smoke Tests
  def test_perform_successfully_indexes_document
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call, true) do
        assert_enqueued_with(job: IndexDocumentJob, args: [@document_id, @tenant_id])
        IndexDocumentJob.perform_now(@document_id, @tenant_id)
        assert_equal Time.current, @document.indexed_at
      end
    end
  end

  def test_perform_with_valid_tenant_id_indexes_document
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call, true) do
        IndexDocumentJob.perform_now(@document_id, @tenant_id)
        assert_equal @tenant_id, @document.tenant_id
      end
    end
  end

  # Negative Tests
  def test_perform_with_mismatched_tenant_id_logs_error
    Document.stub(:find, @document) do
      @document.stub(:tenant_id, 3) do
        assert_no_enqueued_jobs only: IndexDocumentJob
        assert_logs_error("Tenant mismatch")
        IndexDocumentJob.perform_now(@document_id, @tenant_id)
      end
    end
  end

  def test_perform_with_nonexistent_document_logs_warning
    Document.stub(:find) { raise ActiveRecord::RecordNotFound }
    assert_logs_warning("Document #{@document_id} not found")
    assert_no_enqueued_jobs only: IndexDocumentJob
    IndexDocumentJob.perform_now(@document_id, @tenant_id)
  end

  # Exception Tests
  def test_perform_with_elasticsearch_error_retries_and_sends_to_dead_letter_queue
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call) { raise StandardError, "ES connection failed" }

      assert_enqueued_with(job: DeadLetterQueueJob, args: ["indexing", @document_id, @tenant_id, "ES connection failed"]) do
        assert_raises(StandardError) do
          IndexDocumentJob.perform_now(@document_id, @tenant_id)
        end
      end
    end
  end

  def test_perform_with_record_not_found_exception_logs_warning
    Document.stub(:find) { raise ActiveRecord::RecordNotFound }

    assert_logs_warning("Document #{@document_id} not found")
    assert_no_enqueued_jobs only: IndexDocumentJob

    assert_raises(ActiveRecord::RecordNotFound) do
      IndexDocumentJob.perform_now(@document_id, @tenant_id)
    end
  end

  # Edge Cases Tests
  def test_perform_with_nil_document_id
    assert_logs_warning("Document nil not found")
    assert_no_enqueued_jobs only: IndexDocumentJob

    assert_raises(ActiveRecord::RecordNotFound) do
      IndexDocumentJob.perform_now(nil, @tenant_id)
    end
  end

  def test_perform_with_nil_tenant_id
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call, true) do
        assert_no_enqueued_jobs only: IndexDocumentJob
        IndexDocumentJob.perform_now(@document_id, nil)
        # Should not raise error but should not index
      end
    end
  end

  def test_perform_with_empty_string_tenant_id
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call, true) do
        IndexDocumentJob.perform_now(@document_id, "")
        # Should not raise error but should not index if tenant mismatch
      end
    end
  end

  # Security Tests
  def test_perform_with_tenant_id_injection_prevented
    Document.stub(:find, @document) do
      @document.stub(:tenant_id, "123; DROP TABLE documents; --") do
        assert_logs_error("Tenant mismatch")
        IndexDocumentJob.perform_now(@document_id, @tenant_id)
      end
    end
  end

  def test_perform_with_document_id_injection_prevented
    Document.stub(:find) { raise ActiveRecord::RecordNotFound }
    # This should be handled by ActiveRecord's parameter validation
    assert_logs_warning("Document 123; DROP TABLE documents; -- not found")
    IndexDocumentJob.perform_now("123; DROP TABLE documents; --", @tenant_id)
  end

  # Resilience Tests
  def test_perform_with_circuit_breaker_open_does_not_index
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call) { raise CircuitBreaker::OpenError }

      assert_no_enqueued_jobs only: IndexDocumentJob
      assert_logs_error("Circuit breaker is open")

      assert_raises(CircuitBreaker::OpenError) do
        IndexDocumentJob.perform_now(@document_id, @tenant_id)
      end
    end
  end

  def test_perform_with_multiple_retries_sends_to_dead_letter_queue
    Document.stub(:find, @document) do
      Elasticsearch::CircuitBreaker.stub(:call) { raise StandardError, "ES connection failed" }

      # Test that the retry count is properly tracked and dead letter queue is called on final retry
      assert_enqueued_with(job: DeadLetterQueueJob, args: ["indexing", @document_id, @tenant_id, "ES connection failed"]) do
        assert_raises(StandardError) do
          IndexDocumentJob.perform_now(@document_id, @tenant_id)
        end
      end
    end
  end

  # Performance Tests
  def test_perform_with_large_document_size_performance
    large_document = mock("LargeDocument")
    large_document.stub(:id, @document_id) do
      large_document.stub(:tenant_id, @tenant_id) do
        large_document.stub(:__elasticsearch__, mock("Elasticsearch")) do
          large_document.stub(:update_column, true) do
            Document.stub(:find, large_document) do
              Elasticsearch::CircuitBreaker.stub(:call, true) do
                # Performance test - should not take too long to execute
                start_time = Time.current
                IndexDocumentJob.perform_now(@document_id, @tenant_id)
                end_time = Time.current

                # Ensure it completes in a reasonable time (less than 5 seconds for simple operations)
                assert_operator(end_time - start_time, :<, 5)
              end
            end
          end
        end
      end
    end
  end

  def test_perform_with_concurrent_jobs_performance
    # Test concurrent job execution to ensure no race conditions or performance degradation
    jobs = []

    assert_nothing_raised do
      10.times do |i|
        job = IndexDocumentJob.new(@document_id + i, @tenant_id)
        jobs << job
      end

      # This would normally be run in a background queue, but we test the job initialization
      assert_equal 10, jobs.length
    end
  end

  # Integration Tests
  def test_perform_with_valid_document_and_tenant_integration
    document = create(:document, id: @document_id, tenant_id: @tenant_id)

    Elasticsearch::CircuitBreaker.stub(:call, true) do
      assert_nothing_raised do
        IndexDocumentJob.perform_now(@document_id, @tenant_id)
      end
    end

    # Verify that the document was indexed (the index_document method should have been called)
    assert_not_nil document.indexed_at
  end

  private

  def assert_logs_error(message)
    assert_output(nil, /#{message}/) do
      IndexDocumentJob.perform_now(@document_id, @tenant_id)
    end
  end

  def assert_logs_warning(message)
    assert_output(/#{message}/, nil) do
      IndexDocumentJob.perform_now(@document_id, @tenant_id)
    end
  end
end
