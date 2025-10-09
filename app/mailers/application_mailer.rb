# This class serves as the base for creating application-specific mailers.
# It extends ActionMailer::Base and provides a foundation for generating emails in Rails applications.

class ApplicationMailer < ActionMailer::Base
  # The default 'from' address is set to "from@example.com". This value can be overridden when sending individual emails.
  # This is useful for setting the from address consistently across all application mailers.
  def self.default_from(from = "from@example.com")
    # This method sets the default from address for the application. If no from address is provided, it defaults to "from@example.com".
    @default_from_address = from
  end

  # The layout used for this mailer is set to "mailer". This determines the HTML template that will be rendered when generating an email.

  def self.layout(layout_name = "mailer")
    # If a custom layout name is provided, it overwrites the default layout set in this class.
    @layout_name = layout_name
  end

  # This method returns the current default from address for the application.

  def self.default_from_address
    # Returns the current default from address. This value can be accessed directly on the ApplicationMailer class.

    @default_from_address || "from@example.com"
  end

  # This method returns the current layout name used for this mailer.

  def self.layout_name
    # Returns the current layout name. This value can be accessed directly on the ApplicationMailer class.

    @layout_name || "mailer"
  end
end
