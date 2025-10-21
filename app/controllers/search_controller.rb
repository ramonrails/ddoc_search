# frozen_string_literal: true

# Class responsible for handling search requests and rendering search results to the client.
class SearchController < ApplicationController
  # Handles GET requests to the /search endpoint, which is used to perform searches on documents.
  def index
    # Extracts the query parameter from the request parameters. This is the string that will be searched against in the database.
    query = params[:q].to_s.strip

    # Retrieves the page number and per-page limit from the request parameters.
    # If not provided, defaults to page 1 and a per-page limit of 20 documents.
    page = params[:page]&.to_i || 1
    per_page = [params[:per_page]&.to_i || 20, 100].min

    # Checks if the query parameter was provided in the request.
    if query.blank?
      # If not, returns a JSON error response indicating that the 'q' parameter is required.
      render json: { error: "Query parameter 'q' is required" }, status: :bad_request
      return
    end

    # Records the start time of the search operation for performance monitoring purposes.
    start_time = Time.current

    # Performs the actual search on the documents using the Weaviate client.
    results = Document.search_for_tenant(@current_tenant.id, query, page: page, per_page: per_page)

    # Calculates the elapsed time since the search began in milliseconds.
    took_ms = ((Time.current - start_time) * 1000).round

    # Handle both Weaviate and SQL results
    if results.respond_to?(:total)
      # Weaviate results
      total = results.total
      documents = results.records
      SearchAnalyticsJob.perform_later(@current_tenant.id, query, total, took_ms)
    else
      # SQL fallback results (ActiveRecord::Relation)
      total = results.count
      documents = results
      SearchAnalyticsJob.perform_later(@current_tenant.id, query, total, took_ms)
    end

    # Renders a JSON response containing the search results, including the total number of documents matched,
    # the current page and per-page limit, and an array of formatted search result objects.
    render json: {
      query: query,
      total: total,
      page: page,
      per_page: per_page,
      took_ms: took_ms,
      results: documents.map { |doc| format_search_result(doc, results) }
    }
  rescue => e
    # Logs any exceptions that occur during the search operation.
    Rails.logger.error("Search error: #{e.message}")

    # Renders a JSON error response indicating that the search failed.
    render json: {
      error: "Search failed",
      message: e.message
    }, status: :internal_server_error
  end

  # Formats a single search result object from an Elasticsearch hit document.
  private

  def format_search_result(document, search_results)
    # Handle both Weaviate and SQL results
    if search_results.respond_to?(:response)
      # Weaviate results - with scores
      weaviate_docs = search_results.response.dig("data", "Get", Document.weaviate_class_name) || []
      weaviate_doc = weaviate_docs.find { |d| d["title"] == document.title }

      score = weaviate_doc&.dig("_additional", "score")
      # Weaviate doesn't provide highlighting by default, so we'll use truncated content
      snippet = document.content.truncate(200)
    else
      # SQL fallback - no highlighting or scores
      snippet = document.content.truncate(200)
      score = nil
    end

    # Formats a search result object with the ID, title, snippet, score, and created at time
    {
      id: document.id,
      title: document.title,
      snippet: snippet,
      score: score,
      created_at: document.created_at
    }
  end
end
