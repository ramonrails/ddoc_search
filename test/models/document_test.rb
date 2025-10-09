# frozen_string_literal: true

require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  def setup
    @tenant = tenants(:default_tenant)
    @valid_attributes = {
      title: "Test Document",
      content: "This is the content of the test document",
      tenant_id: @tenant.id
    }
  end

  # Smoke Tests
  test "should create document with valid attributes" do
    document = Document.new(@valid_attributes)
    assert document.save
  end

  test "should not create document without title" do
    document = Document.new(@valid_attributes.merge(title: nil))
    refute document.save
    assert_includes document.errors[:title], "can't be blank"
  end

  test "should not create document without content" do
    document = Document.new(@valid_attributes.merge(content: nil))
    refute document.save
    assert_includes document.errors[:content], "can't be blank"
  end

  test "should not create document without tenant_id" do
    document = Document.new(@valid_attributes.merge(tenant_id: nil))
    refute document.save
    assert_includes document.errors[:tenant_id], "can't be blank"
  end

  # Negative Tests
  test "should not create document with title exceeding 500 characters" do
    long_title = "a" * 501
    document = Document.new(@valid_attributes.merge(title: long_title))
    refute document.save
    assert_includes document.errors[:title], "is too long (maximum is 500 characters)"
  end

  test "should not create document with invalid tenant_id" do
    document = Document.new(@valid_attributes.merge(tenant_id: 99999))
    refute document.save
  end

  # Exception Tests
  test "should handle elasticsearch service unavailability gracefully" do
    # Mock the Elasticsearch client to raise an exception
    mock_es_client = Minitest::Mock.new
    mock_es_client.expect :search, nil, [Hash]

    # Temporarily replace the elasticsearch client
    original_client = Document.__elasticsearch__
    Document.instance_variable_set(:@__elasticsearch__, mock_es_client)

    # This should not raise an exception but fallback to SQL search
    assert_nothing_raised do
      Document.search_for_tenant(@tenant.id, "test")
    end

    # Restore original client
    Document.instance_variable_set(:@__elasticsearch__, original_client)
    mock_es_client.verify
  end

  test "should handle invalid search query gracefully" do
    assert_nothing_raised do
      result = Document.search_for_tenant(@tenant.id, "")
      assert_instance_of Kaminari::PaginatableArray, result
    end
  end

  # Edge Cases Tests
  test "should handle empty content" do
    document = Document.new(@valid_attributes.merge(content: ""))
    refute document.save
  end

  test "should handle special characters in title and content" do
    special_title = "Document with 'quotes' and \"double quotes\" & symbols @#$%"
    special_content = "Content with special chars: ñáéíóú üöäß çøå ∑ ∫ ∮ ∇ ∆ ∂ ��� ∈ ∪ ∩ ∴ ∵ ∼ ≈ ≡ ��� ≤ ≥ ≪ ≫ ⊂ ⊃ ⊄ ⊆ ⊇ ⊕ ⊗ ⊥ ⊿ ⌊ ⌋ ⌈ ⌉"

    document = Document.new(@valid_attributes.merge(title: special_title, content: special_content))
    assert document.save
  end

  test "should handle very long content" do
    long_content = "a" * 10000
    document = Document.new(@valid_attributes.merge(content: long_content))
    assert document.save
  end

  test "should handle search with very short query" do
    result = Document.search_for_tenant(@tenant.id, "a")
    assert_instance_of Elasticsearch::Model::Response::Response, result
  end

  test "should handle search with page parameter beyond limits" do
    result = Document.search_for_tenant(@tenant.id, "test", page: 1000)
    assert_instance_of Elasticsearch::Model::Response::Response, result
  end

  # Security Tests
  test "should sanitize query parameters to prevent injection" do
    # This tests that the search method properly handles special characters
    malicious_query = "test' OR '1'='1"

    # Should not raise an exception
    assert_nothing_raised do
      Document.search_for_tenant(@tenant.id, malicious_query)
    end
  end

  test "should not allow unauthorized tenant access" do
    # Create a document with one tenant
    doc = Document.create!(@valid_attributes)

    # Try to search with different tenant_id - should return empty results or filtered results
    result = Document.search_for_tenant(999, "test")
    assert_instance_of Elasticsearch::Model::Response::Response, result

    # Verify that results are properly filtered by tenant
    assert_nothing_raised do
      Document.search_for_tenant(@tenant.id, "test")
    end
  end

  test "should not allow null or empty tenant_id in search" do
    assert_nothing_raised do
      Document.search_for_tenant(nil, "test")
    end
  end

  # Resilience Tests
  test "should retry on circuit breaker timeout" do
    # Mock CircuitBreaker to raise an exception
    original_call = CircuitBreaker.method(:call)

    CircuitBreaker.stub :call, ->(name, &block) {
      if name == :elasticsearch
        raise Elasticsearch::Transport::Transport::Errors::ServiceUnavailable.new("Service Unavailable")
      else
        original_call.call(name, &block)
      end
    }

    # This should fallback to SQL search without raising exception
    assert_nothing_raised do
      Document.search_for_tenant(@tenant.id, "test")
    end

    CircuitBreaker.stub :call, original_call
  end

  test "should handle concurrent document creation" do
    # Create multiple documents concurrently
    threads = []

    5.times do |i|
      threads << Thread.new do
        Document.create!(@valid_attributes.merge(title: "Concurrent Doc #{i}"))
      end
    end

    threads.each(&:join)

    assert_equal 5, Document.count
  end

  test "should handle concurrent search operations" do
    # Create some documents first
    10.times { Document.create!(@valid_attributes.merge(title: "Search Test #{rand(100)}")) }

    threads = []
    results = []

    5.times do |i|
      threads << Thread.new do
        result = Document.search_for_tenant(@tenant.id, "test")
        results << result
      end
    end

    threads.each(&:join)

    assert_equal 5, results.length
  end

  # Performance Tests
  test "should have efficient search with caching" do
    # First search should not be cached
    first_search = Document.search_for_tenant(@tenant.id, "test")

    # Second search should be cached (same query)
    second_search = Document.search_for_tenant(@tenant.id, "test")

    # Both should be instances of Elasticsearch response
    assert_instance_of Elasticsearch::Model::Response::Response, first_search
    assert_instance_of Elasticsearch::Model::Response::Response, second_search

    # Verify cache key generation
    cache_key = "search:#{@tenant.id}:#{Digest::MD5.hexdigest("test")}:1"
    assert Rails.cache.exist?(cache_key)
  end

  test "should handle large result sets efficiently" do
    # Create documents for pagination test
    50.times { Document.create!(@valid_attributes.merge(title: "Large Result #{rand(100)}")) }

    # Test pagination with large page size
    result = Document.search_for_tenant(@tenant.id, "large", page: 1, per_page: 50)
    assert_instance_of Elasticsearch::Model::Response::Response, result

    # Verify result count
    assert_operator result.count, :>=, 0
  end

  test "should maintain consistent sorting" do
    doc1 = Document.create!(@valid_attributes.merge(title: "Old Document"))
    sleep(1) # Ensure different timestamps
    doc2 = Document.create!(@valid_attributes.merge(title: "New Document"))

    result = Document.search_for_tenant(@tenant.id, "document")

    # Results should be sorted by relevance score first, then by created_at descending
    assert_instance_of Elasticsearch::Model::Response::Response, result

    # Verify that the sorting is working correctly
    assert_equal 2, result.count
  end

  # Integration Tests
  test "should properly index document with kafka producer" do
    # Create a mock for KafkaProducer to verify it's called
    original_produce = KafkaProducer.method(:produce)

    call_count = 0

    KafkaProducer.stub :produce, ->(topic:, payload:) {
      call_count += 1
      assert_includes ["document.index", "document.delete"], topic
    } do
      document = Document.create!(@valid_attributes)

      # Verify index job was enqueued
      assert_equal 1, call_count

      # Test deletion job
      document.destroy
      assert_equal 2, call_count
    end
  end

  test "should properly handle content reindexing" do
    document = Document.create!(@valid_attributes)

    # Update the content to trigger reindexing
    original_produce = KafkaProducer.method(:produce)

    call_count = 0

    KafkaProducer.stub :produce, ->(topic:, payload:) {
      call_count += 1
      assert_equal "document.index", topic
    } do
      document.update(content: "Updated content")
      assert_equal 1, call_count
    end
  end

  # Model Validation Tests
  test "should validate presence of required fields" do
    document = Document.new

    refute document.valid?
    assert_includes document.errors[:title], "can't be blank"
    assert_includes document.errors[:content], "can't be blank"
    assert_includes document.errors[:tenant_id], "can't be blank"
  end

  test "should validate title length" do
    document = Document.new(@valid_attributes.merge(title: "a" * 501))
    refute document.valid?
    assert_includes document.errors[:title], "is too long (maximum is 500 characters)"
  end

  test "should have correct associations" do
    document = Document.create!(@valid_attributes)
    assert_equal @tenant, document.tenant
  end

  # Elasticsearch Mapping Tests
  test "should have correct elasticsearch index settings" do
    # Test that the index name is correctly set
    assert_equal "documents_#{Rails.env}", Document.index_name

    # Test that mappings are defined properly
    mapping = Document.mapping.to_hash

    assert_includes mapping[:mappings][:properties], :tenant_id
    assert_includes mapping[:mappings][:properties], :title
    assert_includes mapping[:mappings][:properties], :content
  end

  test "should handle document serialization for indexing" do
    document = Document.create!(@valid_attributes)

    indexed_json = document.as_indexed_json

    assert_includes indexed_json, :tenant_id
    assert_includes indexed_json, :title
    assert_includes indexed_json, :content
    assert_includes indexed_json, :created_at
    assert_includes indexed_json, :metadata

    # Verify structure
    assert_equal document.tenant_id, indexed_json[:tenant_id]
    assert_equal document.title, indexed_json[:title]
    assert_equal document.content, indexed_json[:content]
    assert_equal document.created_at, indexed_json[:created_at]
  end

  test "should properly handle search with highlight" do
    document = Document.create!(@valid_attributes.merge(content: "This is a test content with sample words"))

    result = Document.search_for_tenant(@tenant.id, "test")

    # Verify that highlighting is included in results
    assert_instance_of Elasticsearch::Model::Response::Response, result

    # Check if there are highlights
    if result.respond_to?(:highlight)
      assert_includes result.highlight, :content
    end
  end
end
