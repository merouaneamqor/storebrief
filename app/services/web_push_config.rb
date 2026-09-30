# frozen_string_literal: true

module WebPushConfig
  module_function

  def public_key
    ENV["VAPID_PUBLIC_KEY"].presence
  end

  def private_key
    ENV["VAPID_PRIVATE_KEY"].presence
  end

  def subject
    ENV.fetch("VAPID_SUBJECT", "mailto:support@vazivo.com")
  end

  def configured?
    public_key.present? && private_key.present?
  end

  def vapid_options
    {
      subject: subject,
      public_key: public_key,
      private_key: private_key
    }
  end
end
