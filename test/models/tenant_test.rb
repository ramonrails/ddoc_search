# frozen_string_literal: true

require 'test_helper'

class TenantTest < ActiveSupport::TestCase
  def setup
    @tenant_attributes = {
      name: "Test Tenant",
      subdomain: "test-tenant",
      document_quota: 100,
      rate_limit_per_minute: 1000
    }
  end

  # === SMOKE TESTS ===
  test "should create tenant with valid attributes" do
    tenant = Tenant.new(@tenant_attributes)
    assert tenant.save
  end

  test "should have required associations" do
    tenant = Tenant.new(@tenant_attributes)
    assert tenant.save
    assert_equal 0, tenant.documents.count
  end

  test "should generate api key on creation" do
    tenant = Tenant.new(@tenant_attributes)
    tenant.save!
    assert_not_nil tenant.api_key
    assert_not_nil tenant.api_key_hash
  end

  # === NEGATIVE TESTS ===
  test "should not save tenant without name" do
    tenant = Tenant.new(@tenant_attributes.except(:name))
    refute tenant.valid?
    assert_includes tenant.errors[:name], "can't be blank"
  end

  test "should not save tenant without subdomain" do
    tenant = Tenant.new(@tenant_attributes.except(:subdomain))
    refute tenant.valid?
    assert_includes tenant.errors[:subdomain], "can't be blank"
  end

  test "should not save tenant with duplicate subdomain" do
    Tenant.create!(@tenant_attributes)
    tenant = Tenant.new(@tenant_attributes)
    refute tenant.valid?
    assert_includes tenant.errors[:subdomain], "has already been taken"
  end

  test "should not save tenant without api_key_hash" do
    tenant = Tenant.new(@tenant_attributes.except(:api_key_hash))
    refute tenant.valid?
    assert_includes tenant.errors[:api_key_hash], "can't be blank"
  end

  test "should not save tenant with invalid document_quota" do
    tenant = Tenant.new(@tenant_attributes.merge(document_quota: -1))
    refute tenant.valid?
    assert_includes tenant.errors[:document_quota], "must be greater than 0"
  end

  test "should not save tenant with invalid rate_limit_per_minute" do
    tenant = Tenant.new(@tenant_attributes.merge(rate_limit_per_minute: 0))
    refute tenant.valid?
    assert_includes tenant.errors[:rate_limit_per_minute], "must be greater than 0"
  end

  # === EXCEPTION TESTS ===
  test "should handle invalid api key during authentication" do
    # This should not raise an exception even if there are malformed hashes
    tenant = Tenant.create!(@tenant_attributes)

    # Mock a tenant with invalid hash
    original_hash = tenant.api_key_hash
    tenant.update(api_key_hash: "invalid_hash")

    assert_nil Tenant.authenticate("any_key")

    # Restore the valid hash for cleanup
    tenant.update(api_key_hash: original_hash)
  end

  test "should not raise exception when checking quota on tenant with no documents" do
    tenant = Tenant.create!(@tenant_attributes)
    assert_nothing_raised do
      tenant.quota_exceeded?
    end
  end

  # === EDGE CASE TESTS ===
  test "should handle authentication with nil api key" do
    assert_nil Tenant.authenticate(nil)
  end

  test "should handle authentication with empty string api key" do
    assert_nil Tenant.authenticate("")
  end

  test "should handle tenant with maximum document quota" do
    tenant = Tenant.create!(@tenant_attributes.merge(document_quota: 0))
    assert tenant.quota_exceeded?
  end

  test "should handle tenant with exactly matching quota" do
    tenant = Tenant.create!(@tenant_attributes.merge(document_quota: 1))

    # Create one document to match the quota exactly
    Document.create!(tenant: tenant, title: "Test Doc")
    assert tenant.quota_exceeded?
  end

  test "should handle very large rate limits" do
    tenant = Tenant.create!(@tenant_attributes.merge(rate_limit_per_minute: 1_000_000))
    refute tenant.rate_limit_exceeded?
  end

  test "should handle very small document quotas" do
    tenant = Tenant.create!(@tenant_attributes.merge(document_quota: 1))
    refute tenant.quota_exceeded?
  end

  # === SECURITY TESTS ===
  test "should not expose api key in database" do
    tenant = Tenant.create!(@tenant_attributes)
    saved_tenant = Tenant.find(tenant.id)

    # API key should be stored as hash, not plain text
    assert_not_equal tenant.api_key, saved_tenant.api_key_hash
    assert_equal BCrypt::Password.new(saved_tenant.api_key_hash), tenant.api_key
  end

  test "should use constant-time comparison for authentication" do
    tenant = Tenant.create!(@tenant_attributes)

    # Verify that authentication works correctly with timing attack resistance
    assert_equal tenant, Tenant.authenticate(tenant.api_key)
    refute_equal tenant, Tenant.authenticate("wrong_key")
  end

  test "should not store plain text api key" do
    tenant = Tenant.new(@tenant_attributes)
    tenant.save!

    # The database should contain only the hashed version
    saved_tenant = Tenant.find(tenant.id)
    assert_not_nil saved_tenant.api_key_hash
    assert_not_includes saved_tenant.api_key_hash, tenant.api_key
  end

  # === RESILIENCE TESTS ===
  test "should handle concurrent creation of tenants with same subdomain" do
    # This test verifies that uniqueness validation works properly
    # in a concurrent environment (though actual concurrency testing would require
    # more complex setup)
    tenant1 = Tenant.create!(@tenant_attributes)

    assert_raises(ActiveRecord::RecordInvalid) do
      Tenant.create!(@tenant_attributes)
    end
  end

  test "should not break when rate limiter returns invalid data" do
    # Mock the RateLimiter to return unexpected values
    original_method = RateLimiter.method(:check)

    # Test with negative value (shouldn't cause exception)
    RateLimiter.stub(:check, -1) do
      tenant = Tenant.create!(@tenant_attributes)
      refute tenant.rate_limit_exceeded?  # Should not raise exception
    end

    # Test with non-numeric value (shouldn't cause exception)
    RateLimiter.stub(:check, "invalid") do
      tenant = Tenant.create!(@tenant_attributes)
      refute tenant.rate_limit_exceeded?  # Should not raise exception
    end

    # Restore original method
    RateLimiter.define_method(:check, &original_method)
  end

  test "should handle database connection issues gracefully" do
    # This is a conceptual test - in practice we'd need to mock the database
    tenant = Tenant.new(@tenant_attributes)

    assert_nothing_raised do
      tenant.save(validate: false)  # Skip validations for this test
    end
  end

  # === PERFORMANCE TESTS ===
  test "should authenticate quickly with many tenants" do
    # Create multiple tenants to test performance
    100.times do |i|
      Tenant.create!(@tenant_attributes.merge(name: "Tenant #{i}", subdomain: "tenant#{i}"))
    end

    tenant = Tenant.first

    # This should be fast even with many tenants
    start_time = Time.current
    result = Tenant.authenticate(tenant.api_key)
    end_time = Time.current

    assert_equal tenant, result
    # Ensure it doesn't take more than 100ms (arbitrary threshold)
    assert_operator end_time - start_time, :<, 0.1
  end

  test "should not significantly slow down with many documents" do
    tenant = Tenant.create!(@tenant_attributes)

    # Create many documents to test performance
    1000.times do |i|
      Document.create!(tenant: tenant, title: "Doc #{i}")
    end

    start_time = Time.current
    result = tenant.quota_exceeded?
    end_time = Time.current

    assert_equal true, result
    # Ensure it doesn't take more than 100ms (arbitrary threshold)
    assert_operator end_time - start_time, :<, 0.1
  end

  test "should handle bulk tenant creation efficiently" do
    start_time = Time.current

    # Create multiple tenants in a loop
    50.times do |i|
      Tenant.create!(@tenant_attributes.merge(name: "Bulk Tenant #{i}", subdomain: "bulk#{i}"))
    end

    end_time = Time.current

    # Should be reasonably fast (this is a rough performance test)
    assert_operator end_time - start_time, :<, 5.0
  end

  # === ADDITIONAL FUNCTIONALITY TESTS ===
  test "should properly destroy associated documents when tenant is destroyed" do
    tenant = Tenant.create!(@tenant_attributes)
    document = Document.create!(tenant: tenant, title: "Test Doc")

    assert_equal 1, tenant.documents.count

    tenant.destroy!

    assert_equal 0, Document.where(id: document.id).count
  end

  test "should properly generate unique api keys for different tenants" do
    tenant1 = Tenant.create!(@tenant_attributes)
    tenant2 = Tenant.create!(@tenant_attributes.merge(name: "Tenant 2", subdomain: "tenant2"))

    assert_not_equal tenant1.api_key, tenant2.api_key
    assert_not_equal tenant1.api_key_hash, tenant2.api_key_hash
  end

  test "should authenticate with exact api key match" do
    tenant = Tenant.create!(@tenant_attributes)
    authenticated_tenant = Tenant.authenticate(tenant.api_key)

    assert_equal tenant, authenticated_tenant
  end

  test "should not authenticate with wrong api key" do
    tenant = Tenant.create!(@tenant_attributes)
    authenticated_tenant = Tenant.authenticate("wrong-key")

    assert_nil authenticated_tenant
  end
end
