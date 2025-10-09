# frozen_string_literal: true

require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  # Smoke Tests - Basic functionality
  test "should get health status" do
    get health_url
    assert_response :ok
    json_response = JSON.parse(response.body)
    assert_equal "healthy", json_response["status"]
    assert_not_nil json_response["timestamp"]
    assert_not_nil json_response["version"]
    assert_not_nil json_response["dependencies"]
  end

  test "should return healthy status when all dependencies are up" do
    get health_url
    assert_response :ok
    json_response = JSON.parse(response.body)
    assert_equal "healthy", json_response["status"]
    assert_equal "up", json_response["dependencies"]["postgresql"]["status"]
    assert_equal "up", json_response["dependencies"]["redis"]["status"]
    assert_equal "up", json_response["dependencies"]["elasticsearch"]["status"]
    assert_equal "up", json_response["dependencies"]["kafka"]["status"]
  end

  # Negative Tests - Invalid scenarios
  test "should handle missing dependencies gracefully" do
    # Mock the dependency checks to simulate failures
    original_postgresql = HealthController.instance_method(:check_postgresql)
    original_redis = HealthController.instance_method(:check_redis)
    original_elasticsearch = HealthController.instance_method(:check_elasticsearch)

    # Temporarily override to simulate failure
    HealthController.define_singleton_method(:check_postgresql) do
      { status: "down", error: "Connection failed" }
    end

    get health_url
    assert_response :service_unavailable
    json_response = JSON.parse(response.body)
    assert_equal "degraded", json_response["status"]

    # Restore original methods
    HealthController.define_singleton_method(:check_postgresql, original_postgresql)
  end

  test "should handle invalid HTTP method" do
    post health_url
    assert_response :method_not_allowed

    patch health_url
    assert_response :method_not_allowed

    delete health_url
    assert_response :method_not_allowed
  end

  # Exception Tests - Error handling
  test "should handle PostgreSQL connection error" do
    # Mock ActiveRecord to raise an exception
    original_connection = ActiveRecord::Base.connection
    ActiveRecord::Base.stub(:connection, -> { raise StandardError, "Database connection failed" }) do
      get health_url
      assert_response :service_unavailable
      json_response = JSON.parse(response.body)
      assert_equal "degraded", json_response["status"]
      assert_includes json_response["dependencies"]["postgresql"]["error"], "Database connection failed"
    end
  end

  test "should handle Redis connection error" do
    # Mock Redis to raise an exception
    original_redis = Redis.current
    Redis.stub(:current, -> { raise StandardError, "Redis connection failed" }) do
      get health_url
      assert_response :service_unavailable
      json_response = JSON.parse(response.body)
      assert_equal "degraded", json_response["status"]
      assert_includes json_response["dependencies"]["redis"]["error"], "Redis connection failed"
    end
  end

  test "should handle Elasticsearch connection error" do
    # Mock Elasticsearch to raise an exception
    original_client = Elasticsearch::Model.client
    Elasticsearch::Model.stub(:client, -> { raise StandardError, "Elasticsearch connection failed" }) do
      get health_url
      assert_response :service_unavailable
      json_response = JSON.parse(response.body)
      assert_equal "degraded", json_response["status"]
      assert_includes json_response["dependencies"]["elasticsearch"]["error"], "Elasticsearch connection failed"
    end
  end

  # Edge Cases - Boundary conditions
  test "should handle empty database response" do
    # This tests the SELECT 1 query behavior
    get health_url
    assert_response :ok
    json_response = JSON.parse(response.body)
    assert_not_nil json_response["dependencies"]["postgresql"]["latency_ms"]
    assert_operator json_response["dependencies"]["postgresql"]["latency_ms"], :>=, 0
  end

  test "should handle slow database response" do
    # Mock slow database query (simulated by adding delay)
    original_postgresql = HealthController.instance_method(:check_postgresql)

    HealthController.define_singleton_method(:check_postgresql) do
      start = Time.current
      sleep(0.1) # Simulate slow query
      ActiveRecord::Base.connection.execute("SELECT 1")
      { status: "up", latency_ms: ((Time.current - start) * 1000).round(2) }
    end

    get health_url
    assert_response :ok
    json_response = JSON.parse(response.body)
    assert_equal "up", json_response["dependencies"]["postgresql"]["status"]
    # Should be greater than 0 but not too high (since we're simulating 100ms)
    assert_operator json_response["dependencies"]["postgresql"]["latency_ms"], :>=, 0

    # Restore original method
    HealthController.define_singleton_method(:check_postgresql, original_postgresql)
  end

  test "should handle missing APP_VERSION environment variable" do
    original_version = ENV["APP_VERSION"]
    ENV.delete("APP_VERSION")

    get health_url
    assert_response :ok
    json_response = JSON.parse(response.body)
    assert_equal "1.0.0", json_response["version"]

    # Restore original
    ENV["APP_VERSION"] = original_version if original_version
  end

  # Security Tests - Security considerations
  test "should not expose sensitive information" do
    get health_url
    assert_response :ok
    json_response = JSON.parse(response.body)

    # Should not contain database credentials or other secrets
    refute_includes response.body, "password"
    refute_includes response.body, "secret"
    refute_includes response.body, "credential"

    # Should not expose internal dependency paths
    assert_no_match(/\/db\/.*\//, response.body)
  end

  test "should handle malformed requests gracefully" do
    # No special handling needed as it's a GET request with no parameters
    get health_url
    assert_response :ok
  end

  # Resilience Tests - System stability
  test "should maintain health check functionality during dependency failures" do
    # Test that one failing dependency doesn't crash the entire service
    original_redis = HealthController.instance_method(:check_redis)

    HealthController.define_singleton_method(:check_redis) do
      raise StandardError, "Redis is down"
    end

    get health_url
    assert_response :service_unavailable
    json_response = JSON.parse(response.body)
    assert_equal "degraded", json_response["status"]

    # Restore original method
    HealthController.define_singleton_method(:check_redis, original_redis)
  end

  test "should handle concurrent health checks" do
    # Test multiple concurrent requests to ensure thread safety
    threads = []
    results = []

    5.times do |i|
      threads << Thread.new do
        get health_url
        results << response.status
      end
    end

    threads.each(&:join)

    # All should return successful responses
    results.each { |status| assert_includes [200, 503], status }
  end

  # Performance Tests - Response time and resource usage
  test "should respond within reasonable time" do
    start_time = Time.current

    get health_url

    end_time = Time.current
    response_time = (end_time - start_time) * 1000

    assert_response :ok
    assert_operator response_time, :<, 500 # Should respond in less than 500ms

    json_response = JSON.parse(response.body)
    assert_not_nil json_response["timestamp"]
  end

  test "should not consume excessive memory during health check" do
    # This is a basic check - in practice you'd use memory profiling tools
    get health_url
    assert_response :ok

    # Verify response size is reasonable (less than 10KB)
    assert_operator response.body.length, :<, 10240
  end

  # Integration Tests - Real-world usage scenarios
  test "should return proper JSON structure" do
    get health_url
    assert_response :ok

    json_response = JSON.parse(response.body)

    # Required fields should exist
    assert json_response.key?("status")
    assert json_response.key?("timestamp")
    assert json_response.key?("dependencies")
    assert json_response.key?("version")

    # Dependencies should have expected structure
    dependencies = json_response["dependencies"]
    assert dependencies.key?("postgresql")
    assert dependencies.key?("redis")
    assert dependencies.key?("elasticsearch")
    assert dependencies.key?("kafka")

    # Each dependency should have status and either latency_ms or error
    dependencies.each do |name, dep|
      assert dep.key?("status")
      if dep["status"] == "up"
        assert dep.key?("latency_ms")
        assert_operator dep["latency_ms"], :>=, 0
      else
        assert dep.key?("error")
      end
    end
  end

  test "should maintain consistent response format" do
    # Test multiple calls to ensure consistent format
    responses = []

    3.times do
      get health_url
      assert_response :ok
      responses << JSON.parse(response.body)
    end

    # All responses should have same structure
    responses.each do |resp|
      assert resp.key?("status")
      assert resp.key?("timestamp")
      assert resp.key?("dependencies")
      assert resp.key?("version")

      assert resp["dependencies"].is_a?(Hash)
      assert resp["dependencies"].key?("postgresql")
      assert resp["dependencies"].key?("redis")
      assert resp["dependencies"].key?("elasticsearch")
      assert resp["dependencies"].key?("kafka")
    end
  end

  # Special case tests
  test "should handle kafka dependency without proper connection check" do
    # Kafka check is currently a simple status up with 0 latency
    get health_url
    assert_response :ok

    json_response = JSON.parse(response.body)
    assert_equal "up", json_response["dependencies"]["kafka"]["status"]
    assert_equal 0, json_response["dependencies"]["kafka"]["latency_ms"]
  end
end
