# frozen_string_literal: true

require 'faraday'

# Simple Weaviate client wrapper using Faraday
class WeaviateClient
  attr_reader :url, :conn

  def initialize(url)
    @url = url
    @conn = Faraday.new(url: url) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def schema
    SchemaAPI.new(self)
  end

  def objects
    ObjectsAPI.new(self)
  end

  def query
    QueryAPI.new(self)
  end

  class SchemaAPI
    def initialize(client)
      @client = client
    end

    def get
      response = @client.conn.get("/v1/schema")
      response.body
    end

    def create(schema)
      response = @client.conn.post("/v1/schema") do |req|
        req.body = schema
      end
      response.body
    end
  end

  class ObjectsAPI
    def initialize(client)
      @client = client
    end

    def create(class_name:, properties:, id: nil)
      payload = {
        class: class_name,
        properties: properties
      }
      payload[:id] = id if id

      response = @client.conn.post("/v1/objects") do |req|
        req.body = payload
      end
      response.body
    end

    def delete(class_name:, id:)
      response = @client.conn.delete("/v1/objects/#{class_name}/#{id}")
      response.status == 204
    end
  end

  class QueryAPI
    def initialize(client)
      @client = client
    end

    def get(class_name:, fields:, limit: 10, offset: 0, bm25: nil, where: nil)
      # Build GraphQL query for Weaviate
      query_parts = []
      query_parts << "limit: #{limit}"
      query_parts << "offset: #{offset}" if offset > 0

      if bm25
        query_parts << "bm25: { query: \"#{bm25[:query]}\" }"
      end

      if where
        where_clause = build_where_clause(where)
        query_parts << "where: #{where_clause}"
      end

      graphql_query = {
        query: "{
          Get {
            #{class_name}(#{query_parts.join(', ')}) {
              #{fields}
            }
          }
        }"
      }

      response = @client.conn.post("/v1/graphql") do |req|
        req.body = graphql_query
      end
      response.body
    end

    private

    def build_where_clause(where)
      operator = where[:operator] || "Equal"
      path = where[:path]
      value_key = where.keys.find { |k| k.to_s.start_with?("value") }
      value = where[value_key]

      value_str = value.is_a?(String) ? "\"#{value}\"" : value.to_s

      "{
        path: [\"#{path.join('", "')}\"],
        operator: #{operator},
        #{value_key}: #{value_str}
      }"
    end
  end
end

WEAVIATE_CLIENT = WeaviateClient.new(
  ENV.fetch("WEAVIATE_URL", "http://localhost:8080")
)

# Schema will be created automatically when needed
# The Document model will handle schema creation

