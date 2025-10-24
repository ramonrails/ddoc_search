# frozen_string_literal: true

# Aerospike connection pool for the application
# Aerospike will be used for caching and rate limiting
require 'aerospike'

AEROSPIKE_POOL = ConnectionPool::Wrapper.new(size: 5, timeout: 3) do
  host = Aerospike::Host.new(
    ENV.fetch("AEROSPIKE_HOST", "localhost"),
    ENV.fetch("AEROSPIKE_PORT", "3200").to_i
  )

  # Create client with policy
  policy = Aerospike::ClientPolicy.new
  policy.timeout = 1.0

  Aerospike::Client.new(host, policy: policy)
end

# Aerospike configuration constants
AEROSPIKE_NAMESPACE = ENV.fetch("AEROSPIKE_NAMESPACE", "ddoc_search")
AEROSPIKE_CACHE_SET = "cache"
AEROSPIKE_RATE_LIMIT_SET = "rate_limit"
