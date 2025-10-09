# frozen_string_literal: true

# DocumentsController is responsible for managing documents within a tenant.
# This controller provides methods to create, show, and destroy documents.

class DocumentsController < ApplicationController
  # Before-action filter to check if the current tenant has exceeded their document quota.
  before_action :check_quota, only: [ :create ]

  # Before-action filter to fetch or load the document based on its ID.
  before_action :set_document, only: [ :show, :destroy ]

  def create
    # Create a new document for the current tenant using the provided parameters.
    document = @current_tenant.documents.build(document_params)

    if document.save
      # If the document is created successfully, return its serialized data in JSON format.
      render json: DocumentSerializer.new(document).serializable_hash,
             status: :created
    else
      # If the document creation fails, return an error response with details of the failed validation.
      render json: {
        error: "Failed to create document",
        details: document.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def show
    # Use Rails caching to fetch or load the requested document from memory. If it's not cached, store it for future use.
    cached_document = Rails.cache.fetch("doc:#{@current_tenant.id}:#{@document.id}", expires_in: 1.hour) do
      @document
    end

    # Return the serialized data of the requested document in JSON format.
    render json: DocumentSerializer.new(cached_document).serializable_hash
  end

  def destroy
    # Delete the requested document from the database and invalidate any cached search results for this tenant.
    @document.destroy

    # Remove the cached document from memory to ensure data consistency.
    Rails.cache.delete("doc:#{@current_tenant.id}:#{@document.id}")
    invalidate_search_cache(@current_tenant.id)

    # Return a successful response without content (204 No Content).
    head :no_content
  end

  private

  def set_document
    # Load the document with the provided ID from the current tenant's collection.
    @document = @current_tenant.documents.find(params[:id])
  end

  def document_params
    # Extract and permit necessary parameters for creating a new document, including metadata.
    params.require(:document).permit(:title, :content, metadata: {})
  end

  def check_quota
    # Check if the current tenant has exceeded their allowed document quota. If so, return an error response with details.
    if @current_tenant.quota_exceeded?
      render json: {
        error: "Document quota exceeded",
        current: @current_tenant.documents.count,
        limit: @current_tenant.document_quota
      }, status: :forbidden
    end
  end

  def invalidate_search_cache(tenant_id)
    # Invalidate all cached search results for the specified tenant. This is typically done after deleting a document.
    pattern = "doc_search:search:#{tenant_id}:*"
    Redis.current.scan_each(match: pattern) do |key|
      # Remove each matching cache key from memory to ensure data consistency.
      Redis.current.del(key)
    end
  end
end
