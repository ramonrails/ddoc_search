# frozen_string_literal: true

# WeaviateSearchResult wraps Weaviate query responses to provide a consistent
# interface similar to Elasticsearch results for compatibility with the SearchController
class WeaviateSearchResult
  attr_reader :response, :tenant_id

  def initialize(response, tenant_id)
    @response = response
    @tenant_id = tenant_id
  end

  # Returns total number of results
  def total
    data = response.dig("data", "Get", Document.weaviate_class_name)
    data&.length || 0
  end

  # Returns the actual document records from the database
  def records
    weaviate_docs = response.dig("data", "Get", Document.weaviate_class_name) || []

    # Extract document IDs from Weaviate response
    # Since we don't store the database ID in Weaviate, we need to match by tenant_id, title, and content
    # For now, we'll fetch all matching documents by tenant and filter
    document_titles = weaviate_docs.map { |doc| doc["title"] }

    Document.where(tenant_id: tenant_id, title: document_titles).to_a
  end

  # Check if this is a Weaviate response (has response method)
  def respond_to?(method, include_private = false)
    method == :response || super
  end
end
