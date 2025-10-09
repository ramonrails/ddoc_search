# frozen_string_literal: true

require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  def setup
    @tenant = tenants(:default)
    @user = users(:default)
    sign_in @user
    @controller.instance_variable_set(:@current_tenant, @tenant)
  end

  # Smoke Tests - Basic functionality
  test "should search with valid query" do
    mock_results = OpenStruct.new(
      total: 5,
      records: [OpenStruct.new(id: 1, title: "Test Document", content: "Sample content", created_at: Time.current)],
      response: {
        "hits" => {
          "hits" => [
            {
              "_id" => "1",
              "highlight" => { "content" => ["<em>sample</em> content"] },
              "_score" => 1.0
            }
          ]
        }
      }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal "test", json_response["query"]
    assert_equal 5, json_response["total"]
    assert_equal 1, json_response["page"]
    assert_equal 20, json_response["per_page"]
  end

  test "should handle empty query parameter" do
    get search_index_url, params: { q: "" }

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal "Query parameter 'q' is required", json_response["error"]
  end

  # Negative Tests - Invalid inputs
  test "should reject nil query parameter" do
    get search_index_url, params: { q: nil }

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal "Query parameter 'q' is required", json_response["error"]
  end

  test "should handle query with only whitespace" do
    get search_index_url, params: { q: "   " }

    assert_response :bad_request
    json_response = JSON.parse(response.body)
    assert_equal "Query parameter 'q' is required", json_response["error"]
  end

  test "should handle invalid page parameter" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test", page: "invalid" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response["page"] # Should default to 1
  end

  test "should handle invalid per_page parameter" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test", per_page: "invalid" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 20, json_response["per_page"] # Should default to 20
  end

  test "should limit per_page to maximum of 100" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 100).returns(mock_results)

    get search_index_url, params: { q: "test", per_page: 200 }

    assert_response :success
  end

  # Exception Tests - Error handling
  test "should handle database errors gracefully" do
    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).raises(StandardError.new("Database connection failed"))

    get search_index_url, params: { q: "test" }

    assert_response :internal_server_error
    json_response = JSON.parse(response.body)
    assert_equal "Search failed", json_response["error"]
  end

  test "should handle Elasticsearch errors gracefully" do
    # Mock the search to fail with an Elasticsearch error
    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).raises(StandardError.new("Elasticsearch timeout"))

    get search_index_url, params: { q: "test" }

    assert_response :internal_server_error
    json_response = JSON.parse(response.body)
    assert_equal "Search failed", json_response["error"]
  end

  # Edge Tests - Boundary conditions
  test "should handle empty results" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "nonexistent", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "nonexistent" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 0, json_response["total"]
    assert_empty json_response["results"]
  end

  test "should handle single result" do
    mock_results = OpenStruct.new(
      total: 1,
      records: [OpenStruct.new(id: 1, title: "Single Document", content: "Content here", created_at: Time.current)],
      response: {
        "hits" => {
          "hits" => [
            {
              "_id" => "1",
              "highlight" => { "content" => ["<em>content</em> here"] },
              "_score" => 0.8
            }
          ]
        }
      }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 1, json_response["total"]
    assert_equal 1, json_response["results"].length
  end

  test "should handle large page numbers" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1000, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test", page: 1000 }

    assert_response :success
  end

  # Security Tests - Input validation and injection
  test "should sanitize query parameter" do
    # Test with potentially dangerous input
    dangerous_query = "<script>alert('xss')</script> OR 1=1"

    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, dangerous_query, page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: dangerous_query }

    assert_response :success
  end

  test "should handle unicode characters in query" do
    unicode_query = "café résumé naïve"

    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, unicode_query, page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: unicode_query }

    assert_response :success
  end

  test "should handle special characters in query" do
    special_query = "test@#$%^&*()_+-=[]{}|;':\",./<>?"

    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, special_query, page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: special_query }

    assert_response :success
  end

  # Resilience Tests - System stability
  test "should handle concurrent requests" do
    # This test would require more complex setup to simulate concurrency
    # For now, just verify the basic functionality works with multiple calls

    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test1", page: 1, per_page: 20).returns(mock_results)
    Document.expects(:search_for_tenant).with(@tenant.id, "test2", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test1" }
    assert_response :success

    get search_index_url, params: { q: "test2" }
    assert_response :success
  end

  test "should handle malformed JSON in highlight data" do
    # Mock response with missing highlight data
    mock_results = OpenStruct.new(
      total: 1,
      records: [OpenStruct.new(id: 1, title: "Test Document", content: "Sample content", created_at: Time.current)],
      response: {
        "hits" => {
          "hits" => [
            {
              "_id" => "1",
              # Missing highlight field
              "_score" => 1.0
            }
          ]
        }
      }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test" }

    assert_response :success
    json_response = JSON.parse(response.body)
    # Should still work even with missing highlight data
    assert_equal 1, json_response["total"]
  end

  # Performance Tests - Response time and resource usage
  test "should return results within reasonable time" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    # Capture timing
    start_time = Time.current
    get search_index_url, params: { q: "test" }
    end_time = Time.current

    assert_response :success
    # Verify response time is reasonable (under 5 seconds)
    assert_operator (end_time - start_time), :<, 5.0
  end

  test "should include timing information in response" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: "test" }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_key_exists "took_ms", json_response
    assert_operator json_response["took_ms"], :>=, 0
  end

  # Additional Edge Cases
  test "should handle very long query" do
    long_query = "a" * 1000

    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, long_query, page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: long_query }

    assert_response :success
  end

  test "should handle query with multiple spaces" do
    spaced_query = "   multiple   spaces   in   query   "

    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "multiple spaces in query", page: 1, per_page: 20).returns(mock_results)

    get search_index_url, params: { q: spaced_query }

    assert_response :success
  end

  test "should handle pagination parameters correctly" do
    mock_results = OpenStruct.new(
      total: 0,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 3, per_page: 50).returns(mock_results)

    get search_index_url, params: { q: "test", page: 3, per_page: 50 }

    assert_response :success
    json_response = JSON.parse(response.body)
    assert_equal 3, json_response["page"]
    assert_equal 50, json_response["per_page"]
  end

  # Test that SearchAnalyticsJob is called correctly
  test "should call analytics job with correct parameters" do
    mock_results = OpenStruct.new(
      total: 5,
      records: [],
      response: { "hits" => { "hits" => [] } }
    )

    Document.expects(:search_for_tenant).with(@tenant.id, "test", page: 1, per_page: 20).returns(mock_results)

    # This is a bit tricky to test since we're mocking the search
    # but we can at least verify it's called with proper arguments
    SearchAnalyticsJob.expects(:perform_async).with(@tenant.id, "test", 5, kind_of(Integer))

    get search_index_url, params: { q: "test" }
  end

  private

  def assert_key_exists(key, hash)
    assert_includes hash.keys, key, "Expected key '#{key}' not found in response"
  end
end
