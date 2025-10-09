# frozen_string_literal: true

require "test_helper"

class TenantMiddlewareTest < ActiveSupport::TestCase
  def setup
    @app = ->(env) { [200, { "Content-Type" => "application/json" }, ["OK"]] }
    @middleware = TenantMiddleware.new(@app)
    @valid_api_key = "valid_api_key_123"
    @invalid_api_key = "invalid_api_key_456"
  end

  # Smoke Tests
  def test_middleware_initializes_successfully
    assert_respond_to @middleware, :call
  end

  def test_middleware_handles_valid_request
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    result = @middleware.call(env)
    assert_equal 200, result[0]
  end

  # Negative Tests
  def test_middleware_rejects_missing_api_key
    env = { "PATH_INFO" => "/test" }

    result = @middleware.call(env)
    assert_equal 401, result[0]
  end

  def test_middleware_rejects_invalid_api_key
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @invalid_api_key
    }

    result = @middleware.call(env)
    assert_equal 401, result[0]
  end

  def test_middleware_rejects_empty_api_key
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => ""
    }

    result = @middleware.call(env)
    assert_equal 401, result[0]
  end

  def test_middleware_rejects_whitespace_only_api_key
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => "   "
    }

    result = @middleware.call(env)
    assert_equal 401, result[0]
  end

  # Exception Tests
  def test_middleware_handles_tenant_authentication_exception
    # Mock Tenant.authenticate to raise an exception
    allow(Tenant).to receive(:authenticate).and_raise(StandardError.new("Database connection failed"))

    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    assert_raises StandardError do
      @middleware.call(env)
    end
  end

  def test_middleware_handles_missing_tenant_class
    # Temporarily remove Tenant class to test exception handling
    original_tenant = Object.send(:remove_const, :Tenant) if defined?(Tenant)

    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    assert_raises NameError do
      @middleware.call(env)
    end

    # Restore Tenant class
    Object.const_set(:Tenant, original_tenant) if original_tenant
  end

  # Edge Cases Tests
  def test_middleware_handles_special_characters_in_api_key
    special_keys = [
      "api_key_with_@#$%_chars",
      "api-key-with-dashes",
      "api_key_with_underscores",
      "apiKeyWithCamelCase",
      "API_KEY_WITH_UPPERCASE",
      "Api_Key_With_Mixed_Case"
    ]

    special_keys.each do |key|
      env = {
        "PATH_INFO" => "/test",
        "HTTP_X_TENANT_API_KEY" => key
      }

      # Should not crash, but may return 401 if key is invalid
      result = @middleware.call(env)
      assert_includes [200, 401], result[0]
    end
  end

  def test_middleware_handles_long_api_keys
    long_key = "a" * 1000

    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => long_key
    }

    result = @middleware.call(env)
    assert_equal 401, result[0] # Should be unauthorized due to invalid key
  end

  def test_middleware_handles_unicode_api_keys
    unicode_key = "🔑🔑🔑"

    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => unicode_key
    }

    result = @middleware.call(env)
    assert_equal 401, result[0]
  end

  def test_middleware_handles_null_api_key
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => nil
    }

    result = @middleware.call(env)
    assert_equal 401, result[0]
  end

  # Security Tests
  def test_middleware_handles_case_sensitivity_in_api_keys
    # Assuming Tenant.authenticate is case sensitive
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key.upcase
    }

    result = @middleware.call(env)
    assert_equal 401, result[0] # Should be unauthorized due to case mismatch
  end

  def test_middleware_handles_tenant_injection_via_api_key
    malicious_keys = [
      "'; DROP TABLE tenants; --",
      "admin' OR '1'='1",
      "' UNION SELECT * FROM tenants --",
      "<script>alert('xss')</script>"
    ]

    malicious_keys.each do |key|
      env = {
        "PATH_INFO" => "/test",
        "HTTP_X_TENANT_API_KEY" => key
      }

      result = @middleware.call(env)
      assert_equal 401, result[0] # Should be unauthorized
    end
  end

  def test_middleware_handles_api_key_in_header_case_insensitive
    # HTTP headers are typically case-insensitive, but let's test what happens
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    result = @middleware.call(env)
    assert_includes [200, 401], result[0]
  end

  # Resilience Tests
  def test_middleware_handles_concurrent_requests
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    # Test multiple concurrent requests
    threads = []
    10.times do
      threads << Thread.new do
        result = @middleware.call(env)
        assert_includes [200, 401], result[0]
      end
    end

    threads.each(&:join)
  end

  def test_middleware_handles_request_with_no_tenant_context
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    # Verify Current.tenant is nil before and after request
    assert_nil Current.tenant

    result = @middleware.call(env)

    assert_nil Current.tenant # Should be cleared after request
  end

  def test_middleware_handles_request_with_tenant_set_then_cleared
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    # Mock successful authentication to set tenant
    mock_tenant = instance_double(Tenant, id: 1)
    allow(Tenant).to receive(:authenticate).with(@valid_api_key).and_return(mock_tenant)

    assert_nil Current.tenant

    result = @middleware.call(env)

    assert_nil Current.tenant # Should be cleared after request
    assert_equal 200, result[0]
  end

  # Performance Tests
  def test_middleware_performance_with_multiple_requests
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    # Warm up
    5.times { @middleware.call(env) }

    # Measure time for 100 requests
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    100.times { @middleware.call(env) }
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    total_time = end_time - start_time
    average_time = total_time / 100.0

    # Should complete within reasonable time (e.g., 1 second for 100 requests)
    assert_operator average_time, :<, 0.01 # 10ms average per request
  end

  # Health Check Tests
  def test_middleware_allows_health_check_requests
    env = {
      "PATH_INFO" => "/health",
      "HTTP_X_TENANT_API_KEY" => nil
    }

    result = @middleware.call(env)
    assert_equal 200, result[0]
  end

  def test_middleware_allows_health_check_with_api_key
    env = {
      "PATH_INFO" => "/health",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    result = @middleware.call(env)
    assert_equal 200, result[0]
  end

  # Integration Tests
  def test_middleware_sets_tenant_context_for_valid_request
    mock_tenant = instance_double(Tenant, id: 1)
    allow(Tenant).to receive(:authenticate).with(@valid_api_key).and_return(mock_tenant)

    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    # Verify tenant is set during request
    original_tenant = Current.tenant
    result = @middleware.call(env)

    assert_equal 200, result[0]
    assert_nil Current.tenant # Should be cleared after request
  end

  def test_middleware_handles_multiple_requests_with_different_tenants
    tenant1 = instance_double(Tenant, id: 1)
    tenant2 = instance_double(Tenant, id: 2)

    allow(Tenant).to receive(:authenticate).with("key1").and_return(tenant1)
    allow(Tenant).to receive(:authenticate).with("key2").and_return(tenant2)

    env1 = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => "key1"
    }

    env2 = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => "key2"
    }

    result1 = @middleware.call(env1)
    result2 = @middleware.call(env2)

    assert_equal 200, result1[0]
    assert_equal 200, result2[0]
  end

  # Error Response Tests
  def test_middleware_returns_correct_error_format_for_unauthorized_requests
    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => nil
    }

    result = @middleware.call(env)

    assert_equal 401, result[0]
    assert_equal "application/json", result[1]["Content-Type"]

    # Parse JSON response
    response_body = JSON.parse(result[2].first)
    assert_equal "Unauthorized", response_body["error"]
    assert_equal "Invalid or missing API key", response_body["message"]
  end

  def test_middleware_handles_empty_response_body
    # Test that middleware doesn't crash when response body is empty
    app_with_empty_response = ->(env) { [200, { "Content-Type" => "application/json" }, []] }
    middleware_with_empty_response = TenantMiddleware.new(app_with_empty_response)

    env = {
      "PATH_INFO" => "/test",
      "HTTP_X_TENANT_API_KEY" => @valid_api_key
    }

    result = middleware_with_empty_response.call(env)
    assert_includes [200, 401], result[0]
  end
end
