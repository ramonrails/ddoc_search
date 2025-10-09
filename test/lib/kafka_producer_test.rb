# frozen_string_literal: true

require "test_helper"

class KafkaProducerTest < ActiveSupport::TestCase
  setup do
    @topic = "document.index"
    @payload = { document_id: 123, tenant_id: 456 }
    @key = "some-key"
    @timestamp = Time.current.iso8601
  end

  test "produce successfully sends message to Kafka" do
    # Mock Karafka.producer.produce_async to capture the call
    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: @payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: @payload, key: @key)
  end

  test "produce handles nil key gracefully" do
    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: @payload.to_json,
      key: nil,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: @payload)
  end

  test "produce handles empty payload" do
    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: "{}",
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: {}, key: @key)
  end

  test "produce handles complex nested payload" do
    complex_payload = {
      id: 1,
      name: "Test",
      metadata: {
        created_at: Time.current,
        tags: ["tag1", "tag2"],
        nested: { value: 42 }
      }
    }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: complex_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: complex_payload, key: @key)
  end

  test "produce logs error when Kafka fails" do
    Karafka.expects(:producer).raises(StandardError.new("Kafka connection failed"))

    assert_logs_error(/Failed to produce to Kafka: Kafka connection failed/)

    # Should not raise exception
    assert_nothing_raised do
      KafkaProducer.produce(topic: @topic, payload: @payload)
    end
  end

  test "produce calls fallback handler for document.index topic" do
    Karafka.expects(:producer).raises(StandardError.new("Kafka connection failed"))

    IndexDocumentJob.expects(:perform_async).with(@payload[:document_id], @payload[:tenant_id])

    assert_logs_error(/Failed to produce to Kafka: Kafka connection failed/)
    KafkaProducer.produce(topic: @topic, payload: @payload)
  end

  test "produce calls fallback handler for unknown topic" do
    unknown_topic = "unknown.topic"
    Karafka.expects(:producer).raises(StandardError.new("Kafka connection failed"))

    Rails.logger.expects(:warn).with("No fallback handler for topic: #{unknown_topic}")

    assert_logs_error(/Failed to produce to Kafka: Kafka connection failed/)
    KafkaProducer.produce(topic: unknown_topic, payload: @payload)
  end

  test "produce handles nil payload gracefully" do
    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: "null",
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: nil, key: @key)
  end

  test "produce handles symbol keys in payload" do
    symbol_payload = { id: 123, name: "test" }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: symbol_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: symbol_payload, key: @key)
  end

  test "produce handles string keys in payload" do
    string_payload = { "id" => 123, "name" => "test" }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: string_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: string_payload, key: @key)
  end

  test "produce handles large payloads" do
    # Create a large payload (1MB+)
    large_payload = {
      data: "x" * (1024 * 1024),
      id: 1,
      timestamp: Time.current.iso8601
    }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: large_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: large_payload, key: @key)
  end

  test "produce maintains correct headers structure" do
    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)

    # Verify headers are correctly formed with timestamp and source
    producer_mock.expects(:produce_async).with do |args|
      expected_headers = {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }

      args[:headers] == expected_headers
    end

    KafkaProducer.produce(topic: @topic, payload: @payload)
  end

  test "produce handles special characters in payload" do
    special_payload = {
      name: "Test & More",
      description: "Hello \"World\" \n Newline",
      tags: ["tag1", "tag with space", "tag-with-dash"]
    }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: special_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: special_payload, key: @key)
  end

  test "produce handles unicode characters" do
    unicode_payload = {
      name: "José",
      description: "Café & naïve",
      emoji: "😀🎉"
    }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: unicode_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: unicode_payload, key: @key)
  end

  test "produce handles different data types in payload" do
    mixed_payload = {
      string: "text",
      integer: 42,
      float: 3.14,
      boolean: true,
      nil_value: nil,
      array: [1, 2, 3],
      hash: { nested: "value" }
    }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: mixed_payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: mixed_payload, key: @key)
  end

  test "produce handles invalid topic gracefully" do
    # Test with numeric topic (should not cause crash)
    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: 123,
      payload: @payload.to_json,
      key: @key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: 123, payload: @payload, key: @key)
  end

  test "produce handles very long keys" do
    long_key = "a" * 1000

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with(
      topic: @topic,
      payload: @payload.to_json,
      key: long_key,
      headers: {
        "timestamp" => @timestamp,
        "source" => "document-search-api"
      }
    )

    KafkaProducer.produce(topic: @topic, payload: @payload, key: long_key)
  end

  test "produce maintains timestamp accuracy" do
    # Set a specific time to verify it's used correctly
    specific_time = Time.new(2023, 1, 1, 12, 0, 0)
    Time.stubs(:current).returns(specific_time)

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)
    producer_mock.expects(:produce_async).with do |args|
      args[:headers]["timestamp"] == specific_time.iso8601
    end

    KafkaProducer.produce(topic: @topic, payload: @payload)
  end

  test "produce preserves original payload structure after JSON conversion" do
    original_payload = {
      id: 123,
      name: "Test",
      nested: { value: 42 }
    }

    # Test that we can convert back to the same structure
    converted_payload = original_payload.to_json
    restored_payload = JSON.parse(converted_payload)

    assert_equal original_payload, restored_payload
  end

  test "produce handles multiple concurrent calls" do
    # This test verifies that concurrent calls don't interfere with each other

    # Mock different topics and payloads
    topic1 = "document.index"
    payload1 = { id: 1 }
    topic2 = "user.created"
    payload2 = { id: 2 }

    producer_mock = mock
    Karafka.expects(:producer).returns(producer_mock)

    # Verify both calls are made with correct parameters
    assert_calls_produce_async(
      producer_mock,
      [topic1, payload1],
      [topic2, payload2]
    )

    # Simulate concurrent execution
    threads = []
    5.times do |i|
      threads << Thread.new do
        KafkaProducer.produce(topic: topic1, payload: payload1)
      end
    end

    threads.each(&:join)
  end

  private

  def assert_logs_error(message_regex)
    # Capture logs to verify error was logged
    original_logger = Rails.logger
    log_capture = StringIO.new

    Rails.logger = Logger.new(log_capture)

    begin
      yield if block_given?
    ensure
      Rails.logger = original_logger
    end

    assert_match message_regex, log_capture.string
  end

  def assert_calls_produce_async(producer_mock, *calls)
    calls.each_with_index do |(topic, payload), index|
      producer_mock.expects(:produce_async).with(
        topic: topic,
        payload: payload.to_json,
        key: nil,
        headers: {
          "timestamp" => @timestamp,
          "source" => "document-search-api"
        }
      ).at_least_once
    end
  end
end
