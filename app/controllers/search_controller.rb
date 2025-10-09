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

    # Performs the actual search on the documents using the Elasticsearch client.
    results = Document.search_for_tenant(@current_tenant.id, query, page: page, per_page: per_page)

    # Calculates the elapsed time since the search began in milliseconds.
    took_ms = ((Time.current - start_time) * 1000).round

    # Queues a job to update the search analytics for the tenant based on the results of this search.
    SearchAnalyticsJob.perform_async(@current_tenant.id, query, results.total, took_ms)

    # Renders a JSON response containing the search results, including the total number of documents matched,
    # the current page and per-page limit, and an array of formatted search result objects.
    render json: {
      query: query,
      total: results.total,
      page: page,
      per_page: per_page,
      took_ms: took_ms,
      results: results.records.map { |doc| format_search_result(doc, results) }
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
    # Retrieves the highlighted content for the matched document from the Elasticsearch response.
    highlight = search_results.response.dig("hits", "hits")
                  .find { |h| h["_id"] == document.id.to_s }
                  &.dig("highlight", "content")
                  &.first

    # Formats a search result object with the ID, title, snippet (either highlighted content or truncated original content),
    # score, and created at time of the matched document.
    {
      id: document.id,
      title: document.title,
      snippet: highlight || document.content.truncate(200),
      score: search_results.response.dig("hits", "hits")
               .find { |h| h["_id"] == document.id.to_s }
               &.dig("_score"),
      created_at: document.created_at
    }
  end
end
