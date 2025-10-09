# Enable frozen string literals to improve performance and security.
frozen_string_literal: true

# Define a class called SearchAnalyticsJob that inherits from ApplicationJob.
class SearchAnalyticsJob < ApplicationJob
  # Specify the queue name where this job will be executed. In this case, it's the 'analytics' queue.
  queue_as :analytics

  # Define an instance method perform that will be executed when the job is run.
  def perform(tenant_id, query, result_count, took_ms)
    # Log a message to the Rails logger with the search analytics details.
    # This provides visibility into the search performance and results for debugging or monitoring purposes.
    Rails.logger.info(
      "Search Analytics: tenant=#{tenant_id} query='#{query}' " \
      "results=#{result_count} took_ms=#{took_ms}"
    )
  end
end
