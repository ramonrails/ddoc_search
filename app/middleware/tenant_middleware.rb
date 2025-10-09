# frozen_string_literal: true

# This middleware class extracts the tenant from an API key and sets it in the Current context.
class TenantMiddleware
  # Custom exception for unauthorized access. Inherited from StandardError.
  class UnauthorizedError < StandardError; end

  # Initializes the middleware with the application instance.
  def initialize(app)
    @app = app # Store the application instance as an instance variable.
  end

  # The call method is the entry point for this middleware.
  # It's responsible for extracting the tenant from the API key and setting it in the Current context.
  def call(env)
    # Extracts the API key from the HTTP request headers.
    api_key = env["HTTP_X_TENANT_API_KEY"]

    # Skip authentication for health check
    if env["PATH_INFO"] == "/health" # Check if the current path is the health check endpoint.
      return @app.call(env) # If it's a health check, pass the request to the next middleware or application instance.
    end

    # Authenticate tenant using the API key
    if api_key.present? # Check if an API key is present in the request headers.
      tenant = Tenant.authenticate(api_key) # Attempt to authenticate the tenant with the provided API key.

      if tenant # If authentication is successful, set the tenant in the Current context.
        Current.tenant = tenant
      else
        return unauthorized_response # If authentication fails, return an unauthorized response.
      end
    else
      return unauthorized_response # If no API key is present, return an unauthorized response.
    end

    @app.call(env) # Pass the request to the next middleware or application instance with the tenant set in the Current context.
  ensure
    Current.tenant = nil # Clean up by resetting the tenant in the Current context after processing the request.
  end

  private

  # Returns an unauthorized response for missing or invalid API keys.
  def unauthorized_response
    [
      401, # HTTP status code for unauthorized access.
      { "Content-Type" => "application/json" }, # Set the content type to JSON.
      [ { error: "Unauthorized", message: "Invalid or missing API key" }.to_json ] # Return a JSON response with an error message.
    ]
  end
end
