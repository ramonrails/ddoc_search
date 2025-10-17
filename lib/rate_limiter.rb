# frozen_string_literal: true

# RateLimiter implements a sliding window rate limiting algorithm using Redis.
# It tracks request counts per tenant within time windows to prevent abuse.
# The system uses a fixed window size of 60 seconds for each rate limit bucket.
class RateLimiter
  # Defines the time window size in seconds (60 seconds = 1 minute)
  WINDOW_SIZE = 60

  # Checks if a tenant has exceeded the rate limit for the current window
  # Increments the request counter for the tenant and window combination
  # Sets expiration on the key only when the first request is made to avoid premature cleanup
  # Returns the current count of requests for this tenant in the current window
  def self.check(tenant_id)
    # Generate a unique Redis key based on tenant ID and current time window
    key = "rate_limit:#{tenant_id}:#{current_window}"

    # Atomically increment the counter and return the new value
    count = REDIS_POOL.incr(key)

    # Set expiration time to twice the window size (120 seconds) when this is the first request
    # This ensures the key doesn't persist indefinitely if no further requests come in
    REDIS_POOL.expire(key, WINDOW_SIZE * 2) if count == 1

    count
  end

  # Resets all rate limit counters for a specific tenant
  # Removes all keys matching the tenant's pattern from Redis
  def self.reset(tenant_id)
    # Create a pattern to match all rate limit keys for this tenant
    pattern = "rate_limit:#{tenant_id}:*"

    # Scan through Redis keys matching the pattern and delete them all
    REDIS_POOL.scan_each(match: pattern) do |key|
      REDIS_POOL.del(key)
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
