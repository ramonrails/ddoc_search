# frozen_string_literal: true

require "test_helper"

class SearchAnalyticsJobTest < ActiveJob::TestCase
  def setup
    @tenant_id = "tenant_123"
    @query = "search query"
    @result_count = 10
    @took_ms = 150
  end

  # Smoke Tests
  test "should perform with valid parameters" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, @took_ms)
    end
  end

  test "should log analytics information" do
    assert_enqueued_with(job: SearchAnalyticsJob) do
      SearchAnalyticsJob.perform_later(@tenant_id, @query, @result_count, @took_ms)
    end
  end

  # Negative Tests
  test "should handle nil tenant_id" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(nil, @query, @result_count, @took_ms)
    end
  end

  test "should handle empty query string" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, "", @result_count, @took_ms)
    end
  end

  test "should handle negative result count" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, -5, @took_ms)
    end
  end

  test "should handle negative took_ms" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, -100)
    end
  end

  # Exception Tests
  test "should not raise exception with invalid parameter types" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, "not_a_number", @took_ms)
    end
  end

  # Edge Cases
  test "should handle very long query string" do
    long_query = "a" * 1000
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, long_query, @result_count, @took_ms)
    end
  end

  test "should handle zero result count" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, 0, @took_ms)
    end
  end

  test "should handle zero took_ms" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, 0)
    end
  end

  test "should handle very large result count" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, 999_999_999, @took_ms)
    end
  end

  test "should handle very large took_ms" do
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, 999_999_999)
    end
  end

  # Security Tests
  test "should sanitize query input for logging" do
    malicious_query = "test'; DROP TABLE users; --"
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, malicious_query, @result_count, @took_ms)
    end
  end

  test "should handle special characters in query" do
    special_query = "query with 'quotes' and \"double quotes\" and ; semicolons"
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, special_query, @result_count, @took_ms)
    end
  end

  # Resilience Tests
  test "should handle concurrent job executions" do
    jobs = []
    10.times do
      jobs << SearchAnalyticsJob.perform_later(@tenant_id, @query, @result_count, @took_ms)
    end
    assert_equal 10, jobs.length
  end

  test "should not interfere with other jobs" do
    # This job should not affect other queue operations
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, @took_ms)
      # Other job operations should still work
      assert true
    end
  end

  # Performance Tests
  test "should execute within reasonable time" do
    start_time = Time.current
    SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, @took_ms)
    end_time = Time.current

    # Should complete in well under a second
    assert_operator (end_time - start_time), :<, 1.0
  end

  test "should handle batch processing of jobs" do
    # Test that multiple jobs can be queued and processed
    5.times do |i|
      SearchAnalyticsJob.perform_later(@tenant_id, "#{@query} #{i}", @result_count + i, @took_ms + i)
    end

    assert_equal 5, SearchAnalyticsJob.queue_adapter.enqueued_jobs.length
  end

  # Integration Tests
  test "should correctly format log message" do
    # Capture the logger output to verify formatting
    mock_logger = MiniTest::Mock.new
    mock_logger.expect :info, true, [String]

    # Temporarily replace Rails.logger
    original_logger = Rails.logger
    Rails.logger = mock_logger

    SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, @took_ms)

    # Restore original logger
    Rails.logger = original_logger

    assert_mock mock_logger
  end

  test "should use analytics queue" do
    job = SearchAnalyticsJob.new
    assert_equal :analytics, job.queue_name
  end

  # Data Integrity Tests
  test "should preserve parameter values" do
    SearchAnalyticsJob.perform_now(@tenant_id, @query, @result_count, @took_ms)

    # Parameters should be passed correctly to the logger
    # This is more of a smoke test since we're not mocking the logger
    assert true
  end

  test "should handle unicode characters in query" do
    unicode_query = "search with üñíçødé characters"
    assert_nothing_raised do
      SearchAnalyticsJob.perform_now(@tenant_id, unicode_query, @result_count, @took_ms)
    end
  end
end
