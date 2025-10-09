# frozen_string_literal: true

# Document model represents a document entity within a tenant context.
# It integrates with Elasticsearch for full-text search capabilities and uses Kafka for asynchronous indexing/deletion operations.
class Document < ApplicationRecord
  include Elasticsearch::Model

  # Establishes a belongs_to association with Tenant, indicating that each document belongs to one tenant.
  belongs_to :tenant

  # Validates presence and length of the title field (max 500 characters).
  validates :title, presence: true, length: { maximum: 500 }

  # Ensures content is present for a document.
  validates :content, presence: true

  # Ensures tenant_id is present for a document.
  validates :tenant_id, presence: true

  # Triggers indexing job after a document is created.
  after_create :enqueue_indexing_job

  # Triggers reindexing job only when content has changed after an update.
  after_update :enqueue_reindexing_job, if: :saved_change_to_content?

  # Triggers deletion job after a document is destroyed.
  after_destroy :enqueue_deletion_job

  # Sets the Elasticsearch index name to be unique per Rails environment.
  index_name "documents_#{Rails.env}"

  # Configures Elasticsearch settings for the index including shard count, replica count,
  # refresh interval and custom analyzer with standard tokenizer and filters for text processing.
  settings index: {
    number_of_shards: 10,
    number_of_replicas: 2,
    refresh_interval: "5s",
    analysis: {
      analyzer: {
        custom_analyzer: {
          type: "custom",
          tokenizer: "standard",
          filter: [ "lowercase", "asciifolding", "snowball" ]
        }
      }
    }
  } do
    # Defines the mapping for fields in Elasticsearch index.
    # Dynamic mapping is disabled to ensure strict control over schema.
    mappings dynamic: false do
      # tenant_id is indexed as a keyword for exact matching and filtering.
      indexes :tenant_id, type: :keyword

      # title is stored as both text (with custom analyzer) and keyword (for exact match).
      indexes :title, type: :text, analyzer: :custom_analyzer do
        indexes :keyword, type: :keyword
      end

      # content is indexed with term vector enabled for highlighting search results.
      indexes :content, type: :text, analyzer: :custom_analyzer, term_vector: :with_positions_offsets

      # created_at is indexed as a date for sorting and filtering by time.
      indexes :created_at, type: :date

      # metadata field is stored as an object but disabled to prevent indexing.
      indexes :metadata, type: :object, enabled: false
    end
  end

  # Prepares the document's data for indexing in Elasticsearch.
  # Includes tenant_id, title, content, created_at and metadata fields.
  def as_indexed_json(options = {})
    {
      tenant_id: tenant_id,
      title: title,
      content: content,
      created_at: created_at,
      metadata: metadata || {}
    }
  end

  # Performs a search within the specified tenant for documents matching the query.
  # Includes caching to reduce redundant Elasticsearch queries.
  # Falls back to SQL-based search in case of Elasticsearch service unavailability.
  def self.search_for_tenant(tenant_id, query, page: 1, per_page: 20)
    cache_key = "search:#{tenant_id}:#{Digest::MD5.hexdigest(query)}:#{page}"

    # Caches the search result for 10 minutes to avoid repeated Elasticsearch calls.
    Rails.cache.fetch(cache_key, expires_in: 10.minutes) do
      search_definition = {
        query: {
          bool: {
            must: [
              {
                multi_match: {
                  query: query,
                  fields: [ "title^2", "content" ],
                  type: "best_fields",
                  fuzziness: "AUTO"
                }
              }
            ],
            filter: [
              { term: { tenant_id: tenant_id } }
            ]
          }
        },
        highlight: {
          fields: {
            content: {
              fragment_size: 150,
              number_of_fragments: 3
            }
          }
        },
        from: (page - 1) * per_page,
        size: per_page,
        sort: [
          { _score: { order: :desc } },
          { created_at: { order: :desc } }
        ]
      }

      # Executes the search using circuit breaker to prevent cascading failures.
      CircuitBreaker.call(:elasticsearch) do
        __elasticsearch__.search(search_definition)
      end
  rescue Elasticsearch::Transport::Transport::Errors::ServiceUnavailable
      # Falls back to SQL-based LIKE search when Elasticsearch is unavailable.
    where(tenant_id: tenant_id)
      .where("title ILIKE ? OR content ILIKE ?", "%#{query}%", "%#{query}%")
      .page(page)
      .per(per_page)
  end

  private

  # Enqueues a Kafka message to index the document in Elasticsearch.
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

  # Enqueues a Kafka message to delete the document from Elasticsearch.
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
