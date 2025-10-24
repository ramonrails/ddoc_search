# frozen_string_literal: true

require 'active_support/cache'
require 'aerospike'

# Custom Rails cache store implementation using Aerospike
# Provides a drop-in replacement for Redis cache store
class AerospikeCacheStore < ActiveSupport::Cache::Store
  def initialize(options = {})
    super(options)
    @namespace = options[:namespace] || 'cache'
    @expires_in = options[:expires_in] || 600 # 10 minutes default
    @aerospike_namespace = AEROSPIKE_NAMESPACE
    @aerospike_set = AEROSPIKE_CACHE_SET
  end

  # Read a value from the cache
  def read_entry(key, **options)
    normalized_key = normalize_key(key, options)

    begin
      aerospike_key = Aerospike::Key.new(@aerospike_namespace, @aerospike_set, normalized_key)
      record = AEROSPIKE_POOL.get(aerospike_key)

      return nil unless record

      # Return the cached value
      ActiveSupport::Cache::Entry.new(record.bins['value'])
    rescue Aerospike::Exceptions::Aerospike => e
      Rails.logger.error("Aerospike read error: #{e.message}")
      nil
    end
  end

  # Write a value to the cache
  def write_entry(key, entry, **options)
    normalized_key = normalize_key(key, options)
    ttl = options[:expires_in] || @expires_in

    begin
      aerospike_key = Aerospike::Key.new(@aerospike_namespace, @aerospike_set, normalized_key)
      bins = { 'value' => entry.value }
      write_policy = Aerospike::WritePolicy.new(expiration: ttl.to_i)

      AEROSPIKE_POOL.put(aerospike_key, bins, write_policy)
      true
    rescue Aerospike::Exceptions::Aerospike => e
      Rails.logger.error("Aerospike write error: #{e.message}")
      false
    end
  end

  # Delete a value from the cache
  def delete_entry(key, **options)
    normalized_key = normalize_key(key, options)

    begin
      aerospike_key = Aerospike::Key.new(@aerospike_namespace, @aerospike_set, normalized_key)
      AEROSPIKE_POOL.delete(aerospike_key)
      true
    rescue Aerospike::Exceptions::Aerospike => e
      Rails.logger.error("Aerospike delete error: #{e.message}")
      false
    end
  end

  # Clear all entries in the cache (truncate the set)
  def clear(options = nil)
    begin
      # Aerospike doesn't have a simple "clear all" operation
      # We would need to scan and delete, or use truncate (requires server configuration)
      # For now, we'll log a warning
      Rails.logger.warn("Clear operation not fully implemented for Aerospike cache store")
      true
    rescue Aerospike::Exceptions::Aerospike => e
      Rails.logger.error("Aerospike clear error: #{e.message}")
      false
    end
  end

  private

  # Normalize the cache key to include namespace
  def normalize_key(key, options)
    "#{@namespace}:#{key}"
  end
end
