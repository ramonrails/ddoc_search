# frozen_string_literal: true

class HealthController < ApplicationController
  # Skip authentication checks for health endpoint to allow anonymous access.
  skip_before_action :set_tenant, :check_rate_limit

  def show
    # Check status of dependent services and determine overall health.
    dependencies = check_dependencies

    # Determine the overall health based on all dependent service statuses.
    status = dependencies.values.all? { |dep| dep[:status] == "up" } ? "healthy" : "degraded"
    http_status = status == "healthy" ? :ok : :service_unavailable

    # Render a JSON response with detailed information about the health of each service.
    render json: {
      status: status,  # Overall health of dependent services.
      timestamp: Time.current.iso8601,  # Timestamp of last check.
      dependencies: dependencies,  # Detailed status for each dependent service.
      version: ENV.fetch("APP_VERSION", "1.0.0")  # Application version.
    }, status: http_status
  end

  private

  # Check the status of all dependent services and return a hash with their status and latency.
  def check_dependencies
    {
      postgresql: check_postgresql,
      weaviate: check_weaviate,
      aerospike: check_aerospike,
      kafka: check_kafka
    }
  end

  # Check PostgreSQL connection status, including database query execution time.
  def check_postgresql
    start = Time.current  # Record the current time for latency calculation.

    # Execute a simple query to test database connectivity and response time.
    ActiveRecord::Base.connection.execute("SELECT 1")
    { status: "up", latency_ms: ((Time.current - start) * 1000).round(2) }  # Successful execution, record latency.
  rescue => e
    # Handle any errors during PostgreSQL connection or query execution.
    { status: "down", error: e.message }  # Record the error message for debugging purposes.
  end

  # Check Weaviate health and response time.
  def check_weaviate
    start = Time.current  # Record the current time for latency calculation.

    # Call the Weaviate client to retrieve schema information to verify connectivity.
    WEAVIATE_CLIENT.schema.get
    { status: "up", latency_ms: ((Time.current - start) * 1000).round(2) }  # Successful execution, record latency.
  rescue => e
    # Handle any errors during Weaviate connection or query execution.
    { status: "down", error: e.message }  # Record the error message for debugging purposes.
  end

  # Check Aerospike service status and response time.
  def check_aerospike
    start = Time.current  # Record the current time for latency calculation.

    # Test Aerospike connectivity by checking if we can connect
    test_key = Aerospike::Key.new(AEROSPIKE_NAMESPACE, "health_check", "test")
    AEROSPIKE_POOL.exists(test_key)
    { status: "up", latency_ms: ((Time.current - start) * 1000).round(2) }  # Successful execution, record latency.
  rescue => e
    # Handle any errors during Aerospike connection or query execution.
    { status: "down", error: e.message }  # Record the error message for debugging purposes.
  end

  # Kafka service is assumed to be up and running (no actual check is performed).
  def check_kafka
    # Return a dummy response with "up" status, as no actual check is performed.
    { status: "up", latency_ms: 0 }
  rescue => e
    # Handle any errors during Kafka connection or query execution.
    { status: "down", error: e.message }  # Record the error message for debugging purposes.
  end
end
