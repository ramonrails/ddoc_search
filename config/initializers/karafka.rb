# frozen_string_literal: true

class KarafkaApp < Karafka::App
  setup do |config|
    config.kafka = {
      "bootstrap.servers": ENV.fetch("KAFKA_BROKERS", "localhost:9092"),
      "client.id": "document-search-service"
    }

    config.client_id = "document-search-consumer"
    config.concurrency = 5
  end

  routes.draw do
    topic "document.index" do
      consumer DocumentIndexConsumer
      deserializer ->(message) { JSON.parse(message.raw_payload, symbolize_names: true) }
    end

    topic "document.delete" do
      consumer DocumentIndexConsumer
      deserializer ->(message) { JSON.parse(message.raw_payload, symbolize_names: true) }
    end
  end
end
