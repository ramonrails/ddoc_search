# frozen_string_literal: true

# Redis connection pool for the application
REDIS_POOL = ConnectionPool::Wrapper.new(size: 5, timeout: 3) do
  Redis.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    timeout: 1,
    reconnect_attempts: 3
  )
end
