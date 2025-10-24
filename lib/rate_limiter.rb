# frozen_string_literal: true

# RateLimiter implements a sliding window rate limiting algorithm using Aerospike.
# It tracks request counts per tenant within time windows to prevent abuse.
# The system uses a fixed window size of 60 seconds for each rate limit bucket.
class RateLimiter
  # Defines the time window size in seconds (60 seconds = 1 minute)
  WINDOW_SIZE = 60

  # Checks if a tenant has exceeded the rate limit for the current window
  # Increments the request counter for the tenant and window combination
  # Returns the current count of requests for this tenant in the current window
  def self.check(tenant_id)
    # Generate a unique key based on tenant ID and current time window
    key_string = "rate_limit:#{tenant_id}:#{current_window}"

    begin
      aerospike_key = Aerospike::Key.new(AEROSPIKE_NAMESPACE, AEROSPIKE_RATE_LIMIT_SET, key_string)

      # Use Aerospike's atomic increment operation
      # Initialize the counter if it doesn't exist, otherwise increment
      operation = Aerospike::Operation.add(Aerospike::Bin.new('count', 1))
      operate_policy = Aerospike::OperatePolicy.new
      operate_policy.expiration = WINDOW_SIZE * 2 # TTL in seconds
      operate_policy.record_exists_action = Aerospike::RecordExistsAction::UPDATE

      # Perform the operation and get the result
      record = AEROSPIKE_POOL.operate(aerospike_key, [ operation ], operate_policy)

      # Get the updated count from the record
      # After operate with ADD, we need to read the value
      record = AEROSPIKE_POOL.get(aerospike_key)
      count = record&.bins&.fetch('count', 1) || 1

      count
    rescue Aerospike::Exceptions::Aerospike => e
      Rails.logger.error("Aerospike rate limiter error: #{e.message}")
      # Return 0 to allow the request in case of Aerospike failure
      0
    end
  end

  # Resets all rate limit counters for a specific tenant
  # Removes all keys matching the tenant's pattern from Aerospike
  def self.reset(tenant_id)
    begin
      # Scan through Aerospike records matching the pattern and delete them
      # Note: This is less efficient than Redis SCAN, but works
      statement = Aerospike::Statement.new(AEROSPIKE_NAMESPACE, AEROSPIKE_RATE_LIMIT_SET)

      AEROSPIKE_POOL.scan_all(statement) do |record|
        # Check if the key matches the tenant pattern
        if record.key.user_key.to_s.start_with?("rate_limit:#{tenant_id}:")
          AEROSPIKE_POOL.delete(record.key)
        end
      end
    rescue Aerospike::Exceptions::Aerospike => e
      Rails.logger.error("Aerospike rate limiter reset error: #{e.message}")
    end
  end

  private

  # Calculates the current time window by dividing the current timestamp by window size
  # This ensures that requests within the same window are grouped together for rate limiting
  def self.current_window
    Time.current.to_i / WINDOW_SIZE
  end
end

# Custom exception raised when a tenant exceeds the rate limit
class RateLimitExceededError < StandardError; end
