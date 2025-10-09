# frozen_string_literal: true

# Serializer class for Document objects, responsible for transforming document data
# into JSON API format for API responses. This serializer handles the serialization
# of document attributes and includes custom logic for determining indexing status
# and generating unique job identifiers.
class DocumentSerializer
  include FastJsonapi::ObjectSerializer

  # Defines the basic attributes that should be included in the serialized output
  attributes :id, :title, :created_at, :updated_at

  # Custom attribute to expose the tenant ID of the document
  # This allows clients to understand which tenant owns the document
  attribute :tenant_id do |object|
    object.tenant_id
  end

  # Determines whether a document is considered "indexed"
  # A document is indexed if it has an indexed_at timestamp that is present
  # and occurs after the document's updated_at timestamp
  attribute :indexed do |object|
    object.indexed_at.present? && object.indexed_at > object.updated_at
  end

  # Generates a unique indexing job identifier for each document
  # The job ID combines the document ID with a timestamp to ensure uniqueness
  # This helps track specific indexing operations in the system
  attribute :indexing_job_id do |object|
    "job_#{object.id}_#{object.updated_at.to_i}"
  end
end
