# frozen_string_literal: true

# WeaviateSearchable module provides Weaviate integration for ActiveRecord models.
# It handles schema creation, document indexing, and search functionality.
module WeaviateSearchable
  extend ActiveSupport::Concern

  included do
    # Callbacks for automatic indexing
    after_create :enqueue_indexing_job
    after_update :enqueue_reindexing_job, if: :saved_change_to_content?
    after_destroy :enqueue_deletion_job
  end

  class_methods do
    # Weaviate class name based on Rails environment
    def weaviate_class_name
      "Document_#{Rails.env}"
    end

    # Loads the Weaviate schema from JSON file and replaces environment placeholder
    def load_weaviate_schema
      schema_path = Rails.root.join("db", "weaviate_schema.json")
      schema_json = File.read(schema_path)
      schema = JSON.parse(schema_json)

      # Replace the {env} placeholder with the actual Rails environment
      schema["class"] = schema["class"].gsub("{env}", Rails.env)

      schema
    end

    # Ensures Weaviate schema exists for the Document class
    def ensure_weaviate_schema!
      return if schema_exists?

      schema = load_weaviate_schema
      WEAVIATE_CLIENT.schema.create(schema)
    rescue StandardError => e
      Rails.logger.error("Failed to create Weaviate schema: #{e.message}")
    end

    # Check if Weaviate schema exists
    def schema_exists?
      schema = WEAVIATE_CLIENT.schema.get
      schema["classes"]&.any? { |c| c["class"] == weaviate_class_name }
    rescue StandardError
      false
    end

    # Performs a search within the specified tenant for documents matching the query.
    # Includes caching to reduce redundant Weaviate queries.
    # Falls back to SQL-based search in case of Weaviate service unavailability.
    def search_for_tenant(tenant_id, query, page: 1, per_page: 20)
      cache_key = "search:#{tenant_id}:#{Digest::MD5.hexdigest(query)}:#{page}"

      # Caches the search result for 10 minutes to avoid repeated Weaviate calls.
      Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
        # Executes the search using circuit breaker to prevent cascading failures.
        CircuitBreaker.call(:weaviate) do
          offset = (page - 1) * per_page

          # Build the BM25 search query with tenant filter
          where_filter = {
            path: ["tenant_id"],
            operator: "Equal",
            valueInt: tenant_id
          }

          response = WEAVIATE_CLIENT.query.get(
            class_name: weaviate_class_name,
            fields: "tenant_id title content created_at metadata _additional { id score }",
            limit: per_page,
            offset: offset,
            bm25: {
              query: query,
              properties: ["title^2", "content"]
            },
            where: where_filter
          )

          # Transform Weaviate response to match expected format
          WeaviateSearchResult.new(response, tenant_id)
        end
      end
    rescue StandardError => e
      # Falls back to SQL-based LIKE search when Weaviate is unavailable.
      Rails.logger.warn("Weaviate search failed, falling back to SQL: #{e.message}")
      where(tenant_id: tenant_id)
        .where("title LIKE ? OR content LIKE ?", "%#{query}%", "%#{query}%")
        .page(page)
        .per(per_page)
    end
  end

  # Instance methods

  # Prepares the document's data for indexing in Weaviate.
  def to_weaviate_object
    {
      class: self.class.weaviate_class_name,
      properties: {
        tenant_id: tenant_id,
        title: title,
        content: content,
        created_at: created_at.iso8601,
        metadata: metadata || {}
      }
    }
  end

  private

  # Enqueues a Kafka message to index the document in Weaviate.
  def enqueue_indexing_job
    KafkaProducer.produce(
      topic: "document.index",
      payload: {
        document_id: id,
        tenant_id: tenant_id,
        action: "index"
      }
    )
  end

  # Reuses the indexing job method for reindexing to avoid duplication.
  def enqueue_reindexing_job
    enqueue_indexing_job
  end

  # Enqueues a Kafka message to delete the document from Weaviate.
  def enqueue_deletion_job
    KafkaProducer.produce(
      topic: "document.delete",
      payload: {
        document_id: id,
        tenant_id: tenant_id,
        action: "delete"
      }
    )
  end
end
