# frozen_string_literal: true

class DocumentIndexConsumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      # Extract the message payload for processing, assuming it's a JSON string.
      # The `payload` method is used to retrieve the actual data from the message.
      # This data will be used to update or add document metadata in an index.
      doc_payload = message.payload
      # We're expecting the JSON payload to contain specific metadata about the document,
      # such as its ID, title, and author. This data is then extracted into individual variables for clarity.
      # The `doc_id` will be used as a unique identifier when updating or adding documents in the index.
      doc_id = doc_payload['id']
      # Similarly, we're extracting other relevant metadata about the document from the payload.
      title = doc_payload['title']
      author = doc_payload['author']
      # This contains the document data that needs to be indexed
      payload = message.payload

      IndexDocumentJob.perform_async(
        payload[:document_id],
        payload[:tenant_id]
      )
    end
  rescue => e
    Rails.logger.error("Error processing indexing messages: #{e.message}")
  end
end
