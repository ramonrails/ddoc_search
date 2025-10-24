# frozen_string_literal: true

# This class represents a job for indexing documents in Weaviate.
# It takes care of checking document ownership, attempting to index it,
# and logging various events throughout the process.
class IndexDocumentJob < ApplicationJob
  # This is the queue name where this job will be executed. It's named
  # "indexing" which indicates its purpose.
  queue_as :indexing

  # Configure retry attempts for this job
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  # Performs the indexing operation on a document. This is the main
  # method where all the logic resides.
  def perform(document_id, tenant_id)
    # Retrieve the document from the database with the given ID.
    document = Document.find(document_id)

    # Check if the retrieved document belongs to the specified tenant.
    unless document.tenant_id == tenant_id
      # Log an error message if there's a mismatch. This ensures that
      # we don't attempt to index documents for the wrong tenants.
      Rails.logger.error("Tenant mismatch: document #{document_id} belongs to #{document.tenant_id}, not #{tenant_id}")
      return
    end

    # Ensure Weaviate schema exists before indexing
    Document.ensure_weaviate_schema!

    # Use a circuit breaker to limit the number of concurrent indexing attempts.
    CircuitBreaker.call(:weaviate) do
      # Index the document using Weaviate's Ruby client.
      weaviate_object = document.to_weaviate_object

      WEAVIATE_CLIENT.objects.create(
        class_name: Document.weaviate_class_name,
        properties: weaviate_object[:properties]
      )

      # Update the document with a timestamp indicating when it was indexed.
      document.update_column(:indexed_at, Time.current)

      # Log a success message to indicate that the indexing was successful.
      Rails.logger.info("Indexed document #{document_id} for tenant #{tenant_id}")
    end
  rescue ActiveRecord::RecordNotFound
    # If the document doesn't exist in the database, log a warning and skip the indexing attempt.
    Rails.logger.warn("Document #{document_id} not found, skipping indexing")
  rescue => e
    # Catch any other exceptions that might occur during indexing. This includes errors like network connectivity issues or Weaviate client errors.
    Rails.logger.error("Failed to index document #{document_id}: #{e.message}")

    # Re-raise the exception so that ActiveJob can retry the job according to its configuration.
    raise
  end
end

