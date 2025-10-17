# frozen_string_literal: true

Elasticsearch::Model.client = Elasticsearch::Client.new(
  url: ENV.fetch("ELASTICSEARCH_URL", "http://localhost:9200"),
  log: Rails.env.development?,
  retry_on_failure: 3,
  request_timeout: 5
)

# Index creation is handled separately after models are loaded
# Run: rails runner 'Document.__elasticsearch__.create_index! force: true'
