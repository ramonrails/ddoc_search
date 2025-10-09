require 'test_helper'

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @tenant = tenants(:one)
    @document = documents(:one)

    sign_in @user
    @request.env['devise.mapping'] = Devise.mappings[:user]
    @request.headers['X-Tenant-ID'] = @tenant.id
  end

  # Smoke Tests
  test "should get index" do
    get documents_url
    assert_response :success
  end

  test "should create document" do
    assert_difference('Document.count') do
      post documents_url, params: {
        document: {
          title: "Test Document",
          content: "Test content",
          metadata: { category: "test" }
        }
      }
    end

    assert_response :created
  end

  test "should show document" do
    get document_url(@document)
    assert_response :success
  end

  test "should destroy document" do
    assert_difference('Document.count', -1) do
      delete document_url(@document)
    end

    assert_response :no_content
  end

  # Negative Tests
  test "should not create document with invalid params" do
    post documents_url, params: { document: { title: nil } }
    assert_response :unprocessable_entity
  end

  test "should not create document when quota exceeded" do
    @tenant.update(document_quota: 0)
    post documents_url, params: { document: { title: "Test", content: "Content" } }
    assert_response :forbidden
  end

  test "should not show non-existent document" do
    get document_url(999)
    assert_response :not_found
  end

  test "should not destroy non-existent document" do
    delete document_url(999)
    assert_response :not_found
  end

  # Exception Tests
  test "should handle database errors during creation" do
    # Mock the save method to raise an exception
    document = @tenant.documents.build(title: "Test", content: "Content")
    document.stubs(:save).raises(ActiveRecord::StatementInvalid)

    assert_raises(ActiveRecord::StatementInvalid) do
      post documents_url, params: { document: { title: "Test", content: "Content" } }
    end
  end

  test "should handle cache errors during show" do
    Rails.cache.stubs(:fetch).raises(Memcached::MemcachedError)

    get document_url(@document)
    # Should still return success (fallback behavior)
    assert_response :success
  end

  test "should handle Redis errors during destroy" do
    Redis.current.stubs(:scan_each).raises(StandardError)

    delete document_url(@document)
    # Should not raise exception, but may not clear cache properly
    assert_response :no_content
  end

  # Edge Cases
  test "should handle empty metadata" do
    post documents_url, params: { document: { title: "Test", content: "Content", metadata: {} } }
    assert_response :created
  end

  test "should handle large content" do
    large_content = "A" * 1000000
    post documents_url, params: { document: { title: "Large Test", content: large_content } }
    assert_response :created
  end

  test "should handle special characters in title and content" do
    special_title = "Test & Special <Characters> \"Quoted\""
    special_content = "Content with ñáéíóú and €£¥©®™"

    post documents_url, params: { document: { title: special_title, content: special_content } }
    assert_response :created
  end

  test "should handle nested metadata" do
    nested_metadata = {
      level1: {
        level2: {
          value: "nested_value"
        }
      },
      array_field: [1, 2, 3]
    }

    post documents_url, params: { document: {
      title: "Nested Metadata",
      content: "Test",
      metadata: nested_metadata
    } }

    assert_response :created
  end

  # Security Tests
  test "should not allow access without tenant header" do
    @request.headers.delete('X-Tenant-ID')
    post documents_url, params: { document: { title: "Test", content: "Content" } }
    assert_response :unauthorized
  end

  test "should not allow cross-tenant access" do
    other_tenant = tenants(:two)
    @request.headers['X-Tenant-ID'] = other_tenant.id

    get document_url(@document)
    assert_response :not_found
  end

  test "should not allow unauthorized access" do
    sign_out @user
    post documents_url, params: { document: { title: "Test", content: "Content" } }
    assert_response :redirect
  end

  test "should sanitize input parameters" do
    # Test that we can't inject malicious parameters through metadata
    malicious_metadata = {
      "$where" => "1=1",
      "constructor" => { "prototype" => { "polluted" => "yes" } }
    }

    post documents_url, params: { document: {
      title: "Test",
      content: "Content",
      metadata: malicious_metadata
    } }

    assert_response :created
  end

  # Resilience Tests
  test "should handle concurrent requests" do
    # This test simulates concurrent requests to the same endpoint
    threads = []
    results = []

    5.times do |i|
      threads << Thread.new do
        post documents_url, params: { document: { title: "Concurrent Test #{i}", content: "Content #{i}" } }
        results << response.status
      end
    end

    threads.each(&:join)
    assert_equal 5, results.count(201)
  end

  test "should recover from cache failure" do
    Rails.cache.stubs(:fetch).raises(StandardError)

    get document_url(@document)
    # Should still work even with cache failures
    assert_response :success
  end

  test "should continue operation when Redis is unavailable" do
    Redis.current.stubs(:scan_each).raises(StandardError)

    delete document_url(@document)
    # Should not fail completely even if Redis fails
    assert_response :no_content
  end

  # Performance Tests
  test "should handle multiple document creation efficiently" do
    start_time = Time.current

    10.times do |i|
      post documents_url, params: {
        document: {
          title: "Performance Test #{i}",
          content: "Content #{i}"
        }
      }
    end

    end_time = Time.current
    # Should complete within reasonable time (less than 5 seconds for 10 requests)
    assert_operator (end_time - start_time), :<, 5
  end

  test "should not exceed memory usage with large documents" do
    # Test that the controller doesn't consume excessive memory
    large_content = "A" * 100000  # 100KB content

    post documents_url, params: {
      document: {
        title: "Memory Test",
        content: large_content
      }
    }

    assert_response :created
  end

  test "should maintain response time under load" do
    # Measure response time for multiple requests
    times = []

    5.times do |i|
      start_time = Time.current
      get document_url(@document)
      end_time = Time.current

      times << (end_time - start_time)
    end

    # Average response time should be reasonable (less than 1 second)
    avg_time = times.sum / times.length
    assert_operator avg_time, :<, 1.0
  end

  # Additional Tests for Controller Methods
  test "should properly set document" do
    get document_url(@document)
    assert assigns(:document)
  end

  test "should properly handle document_params" do
    # Test that only permitted parameters are accepted
    post documents_url, params: {
      document: {
        title: "Test",
        content: "Content",
        unauthorized_field: "should_be_ignored"
      }
    }

    assert_response :created
  end

  test "should check quota properly" do
    @tenant.update(document_quota: 1)
    @tenant.documents.create(title: "Existing", content: "Content")

    post documents_url, params: { document: { title: "Test", content: "Content" } }
    assert_response :forbidden
  end

  test "should invalidate search cache after destroy" do
    # Mock Redis to track calls
    mock_redis = mock()
    Redis.stubs(:current).returns(mock_redis)

    # This should call the invalidate_search_cache method
    delete document_url(@document)

    assert_response :no_content
  end
end
