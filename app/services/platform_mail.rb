# Platform (Vazivo) SMTP used when a tenant has not configured their own.
# Emails sent this way are marked billed on the notification log.
module PlatformMail
  module_function

  def configured?
    ENV["SMTP_ADDRESS"].present? || Rails.env.development? || Rails.env.test?
  end

  def from_email
    ENV.fetch("MAIL_FROM_ADDRESS", ENV.fetch("MAIL_FROM", "noreply@vazivo.com").to_s[/<([^>]+)>/, 1] || "noreply@vazivo.com")
  end

  def from_address
    ENV.fetch("MAIL_FROM", "Vazivo <#{from_email}>")
  end

  def smtp_settings
    {
      address: ENV.fetch("SMTP_ADDRESS", "localhost"),
      port: ENV.fetch("SMTP_PORT", "1025").to_i,
      domain: ENV["SMTP_DOMAIN"].presence,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", Rails.env.production? ? "true" : "false") == "true"
    }.compact
  end
end
