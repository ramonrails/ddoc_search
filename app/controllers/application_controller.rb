# Class definition for ApplicationController, which serves as a base class for all controllers in the application.
class ApplicationController < ActionController::API

  # Before action filter to set the current tenant based on the API key provided in the request context.
  before_action :set_tenant

  # Before action filter to check if the current tenant has exceeded its rate limit, and raise an exception if it has.
  before_action :check_rate_limit

  # Rescue block for handling ActiveRecord::RecordNotFound errors. Logs the error message and calls the not_found method
  # with the exception object to return a custom response.
  rescue_from ActiveRecord::RecordNotFound do |exception|
    # Log the error message for future debugging purposes.
    Rails.logger.error("Error: #{exception.message}")

    # Call the not_found method with the exception object to return a custom response.
    not_found(exception)
  end

  # Rescue block for handling ActiveRecord::RecordInvalid errors. Calls the unprocessable_entity method
  # to render an error response with validation details.
  rescue_from ActiveRecord::RecordInvalid, with: :unprocessable_entity

  # Rescue block for handling TenantMiddleware::UnauthorizedError exceptions. Calls the unauthorized method
  # to render an error response indicating that the API key is invalid or missing.
  rescue_from TenantMiddleware::UnauthorizedError, with: :unauthorized

  # Rescue block for handling RateLimitExceededError exceptions. Calls the too_many_requests method
  # to render an error response indicating that the rate limit has been exceeded.
  rescue_from RateLimitExceededError, with: :too_many_requests

  private

  # Sets the current tenant based on the API key provided in the request context.
  #
  # @return [Tenant] The current tenant object for the request context.
  def set_tenant
    # Retrieve the current tenant from the request context using the Current.tenant method.
    @current_tenant = Current.tenant

    # If no tenant is found, raise a TenantMiddleware::UnauthorizedError exception with an error message.
    unless @current_tenant
      raise TenantMiddleware::UnauthorizedError, "Invalid or missing API key"
    end
  end

  # Checks if the current tenant has exceeded its rate limit and raises a RateLimitExceededError exception if it has.
  def check_rate_limit
    # Check if the current tenant's rate limit has been exceeded using the rate_limit_exceeded? method.
    if @current_tenant&.rate_limit_exceeded?
      # If the rate limit has been exceeded, raise a RateLimitExceededError exception with an error message.
      raise RateLimitExceededError, "Rate limit exceeded for tenant"
    end
  end

  # Renders an error response indicating that the requested resource was not found.
  #
  # @param [Exception] exception The exception object containing the error message.
  def not_found(exception)
    # Render a JSON response with an error message and a status code of :not_found (404).
    render json: { error: exception.message }, status: :not_found
  end

  # Renders an error response indicating that the requested resource is invalid due to validation errors.
  #
  # @param [Exception] exception The exception object containing the validation details.
  def unprocessable_entity(exception)
    # Render a JSON response with an error message, validation details, and a status code of :unprocessable_entity (422).
      render json: {
      error: "Validation failed",
      details: exception.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  # Renders an error response indicating that the API key is invalid or missing.
  #
  # @param [Exception] exception The exception object containing the error message.
  def unauthorized(exception)
    # Render a JSON response with an error message and a status code of :unauthorized (401).
    render json: { error: exception.message }, status: :unauthorized
  end

  # Renders an error response indicating that the rate limit has been exceeded, including a retry-after header.
  #
  # @param [Exception] exception The exception object containing the error message.
  def too_many_requests(exception)
    # Render a JSON response with an error message, a retry-after header, and a status code of :too_many_requests (429).
    render json: {
      error: exception.message,
      retry_after: 60
    }, status: :too_many_requests
  end
end
