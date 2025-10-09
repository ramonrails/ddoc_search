# frozen_string_literal: true

# Tenant model representing individual customers/organizations
# Each tenant has isolated data and their own quota/rate limits
class Tenant < ApplicationRecord
  # Associations
  # A tenant can have many documents, and when a tenant is destroyed,
  # all associated documents are also destroyed to maintain data integrity
  has_many :documents, dependent: :destroy

  # Validations
  # Ensures that each tenant has a name for identification
  validates :name, presence: true
  # Ensures that the subdomain is unique and present to avoid conflicts in routing
  validates :subdomain, presence: true, uniqueness: true
  # Ensures API key hash is present and unique for secure authentication
  validates :api_key_hash, presence: true, uniqueness: true
  # Validates that document quota is a positive number to ensure meaningful limits
  validates :document_quota, numericality: { greater_than: 0 }
  # Validates that rate limit per minute is a positive number to enforce meaningful throttling
  validates :rate_limit_per_minute, numericality: { greater_than: 0 }

  # Callbacks
  # Generates an API key before validation if the tenant is being created
  before_validation :generate_api_key, on: :create

  # Generate a secure API key and store its hash
  # We never store the actual API key, only its bcrypt hash for security
  def generate_api_key
    return if api_key_hash.present?

    @api_key = SecureRandom.hex(32)  # 64 character API key
    self.api_key_hash = BCrypt::Password.create(@api_key)
  end

  # Return the plain API key (only available after creation)
  attr_reader :api_key

  # Authenticate tenant by API key
  # This uses constant-time comparison to prevent timing attacks
  def self.authenticate(api_key)
    # Find all tenants and check each hash (could be optimized with bloom filter)
    find_each do |tenant|
      return tenant if BCrypt::Password.new(tenant.api_key_hash) == api_key
    rescue BCrypt::Errors::InvalidHash
      next
    end
    nil
  end

  # Check if tenant has reached their document quota
  def quota_exceeded?
    documents.count >= document_quota
  end

  # Check rate limit using Redis
  # Uses a sliding window counter with 1-minute buckets
  def rate_limit_exceeded?
    RateLimiter.check(id) > rate_limit_per_minute
  end
end
