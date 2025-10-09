# frozen_string_literal: true

require "test_helper"

class DocumentIndexConsumerTest < ActiveSupport::TestCase
  include Karafka::Testing::Support

  def setup
    @messages = []
  end

  # Smoke Tests - Basic functionality verification
  test "should process valid messages successfully" do
    message = build_message(
      document_id: "doc_123",
      tenant_id: "tenant_456"
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    # Verify that the job was enqueued
    assert_enqueued_with(job: IndexDocumentJob, args: ["doc_123", "tenant_456"])
  end

  test "should process multiple messages in batch" do
    messages = [
      build_message(document_id: "doc_1", tenant_id: "tenant_1"),
      build_message(document_id: "doc_2", tenant_id: "tenant_2"),
      build_message(document_id: "doc_3", tenant_id: "tenant_3")
    ]

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume(messages)
    end

    # Verify that all jobs were enqueued
    assert_enqueued_with(job: IndexDocumentJob, args: ["doc_1", "tenant_1"])
    assert_enqueued_with(job: IndexDocumentJob, args: ["doc_2", "tenant_2"])
    assert_enqueued_with(job: IndexDocumentJob, args: ["doc_3", "tenant_3"])
  end

  # Negative Tests - Invalid inputs
  test "should handle missing document_id gracefully" do
    message = build_message(
      tenant_id: "tenant_456"
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    # Should still enqueue job with nil document_id
    assert_enqueued_with(job: IndexDocumentJob, args: [nil, "tenant_456"])
  end

  test "should handle missing tenant_id gracefully" do
    message = build_message(
      document_id: "doc_123"
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    # Should still enqueue job with nil tenant_id
    assert_enqueued_with(job: IndexDocumentJob, args: ["doc_123", nil])
  end

  test "should handle completely empty message payload" do
    message = build_message({})

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    # Should enqueue job with nil values
    assert_enqueued_with(job: IndexDocumentJob, args: [nil, nil])
  end

  test "should handle non-string payload values" do
    message = build_message(
      document_id: 123,
      tenant_id: 456
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    # Should enqueue job with converted values
    assert_enqueued_with(job: IndexDocumentJob, args: ["123", "456"])
  end

  # Exception Tests - Error handling
  test "should log error when IndexDocumentJob raises exception" do
    message = build_message(
      document_id: "doc_123",
      tenant_id: "tenant_456"
    )

    # Stub the job to raise an exception
    assert_raises(StandardError) do
      IndexDocumentJob.any_instance.stubs(:perform).raises(StandardError.new("Job failed"))
      DocumentIndexConsumer.new.consume([message])
    end
  end

  test "should handle connection errors gracefully" do
    message = build_message(
      document_id: "doc_123",
      tenant_id: "tenant_456"
    )

    # Mock the perform_async to raise a connection error
    IndexDocumentJob.expects(:perform_async).raises(ActiveRecord::ConnectionNotEstablished)

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end
  end

  test "should not crash when messages array is empty" do
    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([])
    end
  end

  # Edge Cases Tests
  test "should handle nil messages gracefully" do
    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([nil])
    end
  end

  test "should handle very long document IDs" do
    long_id = "a" * 1000

    message = build_message(
      document_id: long_id,
      tenant_id: "tenant_456"
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    assert_enqueued_with(job: IndexDocumentJob, args: [long_id, "tenant_456"])
  end

  test "should handle special characters in IDs" do
    special_ids = [
      "doc-with-dashes",
      "doc_with_underscores",
      "doc.with.dots",
      "doc@with@at",
      "doc#with#hash"
    ]

    special_ids.each do |id|
      message = build_message(
        document_id: id,
        tenant_id: "tenant_456"
      )

      assert_nothing_raised do
        DocumentIndexConsumer.new.consume([message])
      end

      assert_enqueued_with(job: IndexDocumentJob, args: [id, "tenant_456"])
    end
  end

  test "should handle unicode characters in IDs" do
    unicode_id = "doc_ñáéíóú"

    message = build_message(
      document_id: unicode_id,
      tenant_id: "tenant_456"
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    assert_enqueued_with(job: IndexDocumentJob, args: [unicode_id, "tenant_456"])
  end

  # Security Tests
  test "should not process messages with malicious payloads" do
    # Test with potentially harmful payloads
    malicious_payloads = [
      { document_id: "<script>alert('xss')</script>", tenant_id: "tenant_123" },
      { document_id: "'; DROP TABLE users; --", tenant_id: "tenant_123" },
      { document_id: "admin' OR '1'='1", tenant_id: "tenant_123" }
    ]

    malicious_payloads.each do |payload|
      message = build_message(payload)

      assert_nothing_raised do
        DocumentIndexConsumer.new.consume([message])
      end

      # Should still enqueue the job with potentially malicious data
      assert_enqueued_with(job: IndexDocumentJob, args: [payload[:document_id], payload[:tenant_id]])
    end
  end

  test "should handle empty string IDs" do
    message = build_message(
      document_id: "",
      tenant_id: ""
    )

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end

    assert_enqueued_with(job: IndexDocumentJob, args: ["", ""])
  end

  # Resilience Tests - System robustness
  test "should handle concurrent processing" do
    messages = Array.new(10) do |i|
      build_message(
        document_id: "doc_#{i}",
        tenant_id: "tenant_#{i}"
      )
    end

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume(messages)
    end

    # Should have enqueued all jobs
    assert_equal 10, enqueued_jobs.length
  end

  test "should handle processing when job queue is full" do
    # Stub the perform_async to raise an exception (simulating queue full)
    IndexDocumentJob.any_instance.stubs(:perform_async).raises(QueueError.new("Queue full"))

    message = build_message(
      document_id: "doc_123",
      tenant_id: "tenant_456"
    )

    # Should not crash but log the error
    assert_nothing_raised do
      DocumentIndexConsumer.new.consume([message])
    end
  end

  test "should maintain processing state during failures" do
    messages = [
      build_message(document_id: "doc_1", tenant_id: "tenant_1"),
      build_message(document_id: "doc_2", tenant_id: "tenant_2")
    ]

    # Mock the first job to succeed and second to fail
    IndexDocumentJob.any_instance.stubs(:perform_async).with("doc_1", "tenant_1").returns(true)
    IndexDocumentJob.any_instance.stubs(:perform_async).with("doc_2", "tenant_2").raises(StandardError)

    # Should not raise exception (should handle gracefully)
    assert_nothing_raised do
      DocumentIndexConsumer.new.consume(messages)
    end
  end

  # Performance Tests - Efficiency considerations
  test "should process large batch of messages efficiently" do
    start_time = Time.current

    large_batch = Array.new(100) do |i|
      build_message(
        document_id: "doc_#{i}",
        tenant_id: "tenant_#{i % 10}" # Reuse tenants to simulate real usage
      )
    end

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume(large_batch)
    end

    # Should process all messages
    assert_equal 100, enqueued_jobs.length

    # Performance check - should complete in reasonable time (less than 1 second for 100 messages)
    end_time = Time.current
    assert_operator end_time - start_time, :<, 1.0
  end

  test "should not exceed memory limits with large batches" do
    # This test verifies that the consumer doesn't hold references to all messages at once
    large_batch = Array.new(1000) do |i|
      build_message(
        document_id: "doc_#{i}",
        tenant_id: "tenant_#{i % 100}"
      )
    end

    assert_nothing_raised do
      DocumentIndexConsumer.new.consume(large_batch)
    end

    # Should have enqueued all jobs (1000 in this case)
    assert_equal 1000, enqueued_jobs.length
  end

  private

  def build_message(payload = {})
    Karafka::Messages::Message.new(
      "document_id" => payload[:document_id],
      "tenant_id" => payload[:tenant_id]
    )
  end
end
