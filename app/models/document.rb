# frozen_string_literal: true

# Document model represents a document entity within a tenant context.
# It integrates with Weaviate for full-text search capabilities and uses Kafka for asynchronous indexing/deletion operations.
class Document < ApplicationRecord
  # Include Weaviate search functionality
  include WeaviateSearchable

  # Establishes a belongs_to association with Tenant, indicating that each document belongs to one tenant.
  belongs_to :tenant

  # Validates presence and length of the title field (max 500 characters).
  validates :title, presence: true, length: { maximum: 500 }

  # Ensures content is present for a document.
  validates :content, presence: true

  # Ensures tenant_id is present for a document.
  validates :tenant_id, presence: true
end
