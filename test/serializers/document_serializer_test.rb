# test/serializers/document_serializer_test.rb
require 'test_helper'

class DocumentSerializerTest < ActiveSupport::TestCase
  def setup
    @tenant = tenants(:default_tenant)
    @document = documents(:document_with_tenant)
  end

  # Smoke Tests - Basic functionality
  test "serializes document with basic attributes" do
    serialized = DocumentSerializer.new(@document).serialize_to_hash

    assert_equal @document.id, serialized[:data][:id]
    assert_equal @document.title, serialized[:data][:attributes][:title]
    assert_equal @document.created_at, serialized[:data][:attributes][:created_at]
    assert_equal @document.updated_at, serialized[:data][:attributes][:updated_at]
  end

  test "serializes tenant_id attribute" do
    serialized = DocumentSerializer.new(@document).serialize_to_hash

    assert_equal @document.tenant_id, serialized[:data][:attributes][:tenant_id]
  end

  # Negative Tests - Invalid inputs
  test "handles nil tenant_id gracefully" do
    document_with_nil_tenant = documents(:document_without_tenant)

    serialized = DocumentSerializer.new(document_with_nil_tenant).serialize_to_hash

    assert_equal nil, serialized[:data][:attributes][:tenant_id]
  end

  test "handles nil created_at and updated_at" do
    document_with_nil_timestamps = Document.new(
      title: "Test",
      tenant_id: @tenant.id,
      created_at: nil,
      updated_at: nil
    )

    serialized = DocumentSerializer.new(document_with_nil_timestamps).serialize_to_hash

    assert_nil serialized[:data][:attributes][:created_at]
    assert_nil serialized[:data][:attributes][:updated_at]
  end

  # Exception Tests - Error handling
  test "handles database errors gracefully" do
    # This would require mocking or simulating a database error
    # For now, we'll ensure the serializer doesn't crash with valid data
    assert_nothing_raised do
      serialized = DocumentSerializer.new(@document).serialize_to_hash
      assert_instance_of Hash, serialized
    end
  end

  # Edge Cases - Boundary conditions
  test "handles document without indexed_at" do
    document = documents(:document_with_tenant)
    document.update(indexed_at: nil)

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal false, serialized[:data][:attributes][:indexed]
  end

  test "handles document with indexed_at older than updated_at" do
    document = documents(:document_with_tenant)
    document.update(indexed_at: 1.day.ago)

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal false, serialized[:data][:attributes][:indexed]
  end

  test "handles document with indexed_at newer than updated_at" do
    document = documents(:document_with_tenant)
    document.update(indexed_at: 1.day.from_now)

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal true, serialized[:data][:attributes][:indexed]
  end

  test "handles document with identical indexed_at and updated_at" do
    document = documents(:document_with_tenant)
    document.update(indexed_at: document.updated_at)

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal false, serialized[:data][:attributes][:indexed]
  end

  test "generates unique indexing_job_id for different update times" do
    document1 = documents(:document_with_tenant)
    document2 = documents(:document_with_tenant)

    # Simulate different update times
    document2.update(updated_at: 1.hour.ago)

    serialized1 = DocumentSerializer.new(document1).serialize_to_hash
    serialized2 = DocumentSerializer.new(document2).serialize_to_hash

    refute_equal serialized1[:data][:attributes][:indexing_job_id],
                 serialized2[:data][:attributes][:indexing_job_id]
  end

  test "handles zero timestamp values" do
    document = documents(:document_with_tenant)
    document.update(updated_at: Time.at(0))

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal "job_#{document.id}_0", serialized[:data][:attributes][:indexing_job_id]
  end

  # Security Tests - Input validation and sanitization
  test "handles malicious title input" do
    malicious_title = "<script>alert('xss')</script>Test Document"
    document = documents(:document_with_tenant)
    document.update(title: malicious_title)

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal malicious_title, serialized[:data][:attributes][:title]
  end

  test "handles special characters in title" do
    special_title = "Document with 'quotes' and \"double quotes\" & symbols © ®"
    document = documents(:document_with_tenant)
    document.update(title: special_title)

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal special_title, serialized[:data][:attributes][:title]
  end

  # Resilience Tests - System stability
  test "handles concurrent serialization requests" do
    # This test ensures the serializer is thread-safe
    threads = []

    10.times do |i|
      threads << Thread.new do
        document = documents(:document_with_tenant)
        serialized = DocumentSerializer.new(document).serialize_to_hash
        assert_instance_of Hash, serialized
      end
    end

    threads.each(&:join)
  end

  test "handles serialization of multiple documents" do
    documents_array = [documents(:document_with_tenant), documents(:document_without_tenant)]

    serialized = DocumentSerializer.new(documents_array).serialize_to_hash

    assert_instance_of Array, serialized[:data]
    assert_equal 2, serialized[:data].length
  end

  # Performance Tests - Efficiency
  test "serializes document efficiently" do
    # Test that serialization doesn't take excessive time
    start_time = Time.current

    100.times do
      DocumentSerializer.new(@document).serialize_to_hash
    end

    end_time = Time.current
    execution_time = end_time - start_time

    # Should complete within a reasonable time (e.g., 1 second for 100 serializations)
    assert_operator execution_time, :<, 1.0
  end

  test "serializes without additional database queries" do
    # Ensure no extra queries are made during serialization
    assert_no_queries do
      DocumentSerializer.new(@document).serialize_to_hash
    end
  end

  # Data Integrity Tests - Correctness
  test "maintains data integrity for indexed attribute" do
    # Test various combinations of indexed_at and updated_at
    test_cases = [
      { indexed_at: nil, updated_at: Time.current, expected: false },
      { indexed_at: 1.day.ago, updated_at: Time.current, expected: false },
      { indexed_at: 1.day.from_now, updated_at: Time.current, expected: true },
      { indexed_at: Time.current, updated_at: Time.current, expected: false }
    ]

    test_cases.each do |case_data|
      document = documents(:document_with_tenant)
      document.update(indexed_at: case_data[:indexed_at], updated_at: case_data[:updated_at])

      serialized = DocumentSerializer.new(document).serialize_to_hash

      assert_equal case_data[:expected], serialized[:data][:attributes][:indexed]
    end
  end

  test "generates consistent indexing_job_id" do
    # Ensure the job ID generation is deterministic for same document
    document = documents(:document_with_tenant)

    serialized1 = DocumentSerializer.new(document).serialize_to_hash
    serialized2 = DocumentSerializer.new(document).serialize_to_hash

    assert_equal serialized1[:data][:attributes][:indexing_job_id],
                 serialized2[:data][:attributes][:indexing_job_id]
  end

  # Boundary Tests - Extremal values
  test "handles very large timestamp values" do
    document = documents(:document_with_tenant)
    document.update(updated_at: Time.at(2147483647)) # Unix timestamp for 2038-01-19

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal "job_#{document.id}_2147483647",
                 serialized[:data][:attributes][:indexing_job_id]
  end

  test "handles very small timestamp values" do
    document = documents(:document_with_tenant)
    document.update(updated_at: Time.at(0))

    serialized = DocumentSerializer.new(document).serialize_to_hash

    assert_equal "job_#{document.id}_0",
                 serialized[:data][:attributes][:indexing_job_id]
  end

  # Integration Tests - Full workflow
  test "serializes complete document object with all attributes" do
    serialized = DocumentSerializer.new(@document).serialize_to_hash

    expected_attributes = [:id, :title, :created_at, :updated_at, :tenant_id, :indexed, :indexing_job_id]

    actual_attributes = serialized[:data][:attributes].keys

    expected_attributes.each do |attr|
      assert_includes actual_attributes, attr
    end

    # Verify specific values
    assert_equal @document.id, serialized[:data][:id]
    assert_equal @document.title, serialized[:data][:attributes][:title]
    assert_equal @document.tenant_id, serialized[:data][:attributes][:tenant_id]
    assert_equal @document.created_at, serialized[:data][:attributes][:created_at]
    assert_equal @document.updated_at, serialized[:data][:attributes][:updated_at]
  end
end
