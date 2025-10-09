# Enable frozen string literals to improve performance by storing strings in their final form.
frozen_string_literal: true

# Class for thread-safe storage of the current request context.
# This class is used to manage the context of the current request, ensuring that it can be safely accessed from multiple threads.
class Current < ActiveSupport::CurrentAttributes
  # Attribute for storing the tenant associated with the current request. This attribute is used to identify the tenant being served by the application.

  # Define an attribute called 'tenant' to store the current tenant.
  attribute :tenant
end
