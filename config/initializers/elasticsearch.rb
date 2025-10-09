# frozen_string_literal: true

Elasticsearch::Model.client = Elasticsearch::Client.new(
  url: ENV.fetch("ELASTICSEARCH_URL", "http://localhost:9200"),
  log: Rails.env.development?,
  retry_on_failure: 3,
  request_timeout: 5
)

unless Rails.env.test?
  begin
    Document.__elasticsearch__.create_index! force: true if Rails.env.development?
  rescue Elasticsearch::Transport::Transport::Errors::BadRequest => e
    Rails.logger.info("Elasticsearch index already exists")
  end
end
