# frozen_string_literal: true

# This module serves as a producer interface for Kafka messages within the application.
# It provides a centralized way to send messages to Kafka topics with consistent
# payload formatting, headers, and error handling.
module KafkaProducer
  class << self
    # Produces a message to the specified Kafka topic with the given payload.
    # The method handles JSON serialization of the payload and adds standard headers
    # including timestamp and source information. If the production fails, it logs
    # the error and attempts to handle the failure based on the topic.
    #
    # @param topic [String] The Kafka topic to produce the message to
    # @param payload [Hash] The message payload to be sent
    # @param key [String, nil] Optional message key for partitioning
    # @return [void]
    def produce(topic:, payload:, key: nil)
      Karafka.producer.produce_async(
        topic: topic,
        payload: payload.to_json,
        key: key,
        headers: {
          "timestamp" => Time.current.iso8601,
          "source" => "document-search-api"
        }
      )

    rescue => e
      # Log the Kafka production failure for debugging and monitoring purposes
      Rails.logger.error("Failed to produce to Kafka: #{e.message}")
      # Attempt to handle the failure by dispatching a fallback job based on topic
      handle_kafka_failure(topic, payload)
    end

    private

    # Handles failures in Kafka message production by dispatching appropriate
    # fallback jobs based on the topic that failed. This provides resilience
    # by ensuring critical operations are not lost due to temporary Kafka issues.
    #
    # @param topic [String] The Kafka topic that failed to produce to
    # @param payload [Hash] The original payload that failed to be produced
    # @return [void]
    def handle_kafka_failure(topic, payload)
      case topic
      when "document.index"
        # For document indexing failures, dispatch the index document job as fallback
        IndexDocumentJob.perform_async(payload[:document_id], payload[:tenant_id])
      else
        # Log warning for topics without specific fallback handling
        Rails.logger.warn("No fallback handler for topic: #{topic}")
      end
    end
  end
end
