# frozen_string_literal: true

module Vazivo
  # Public legal metadata for Loi 09-08 (CNDP) notices. Organizational filings stay with the operator.
  class Privacy
    class << self
      def contact_email
        raw = ENV["PRIVACY_CONTACT_EMAIL"].presence || default_mailto_email
        raw.to_s.delete_prefix("mailto:")
      end

      def processor_name
        ENV.fetch("DATA_PROCESSOR_NAME", "Vazivo")
      end

      def processor_address
        ENV.fetch("DATA_PROCESSOR_ADDRESS", "")
      end

      def cndp_url
        "https://www.cndp.ma/loi-09-08/"
      end

      def privacy_policy_version
        ENV.fetch("PRIVACY_POLICY_VERSION", "2026-10-11")
      end

      private

      def default_mailto_email
        subject = ENV.fetch("VAPID_SUBJECT", "mailto:support@vazivo.com")
        subject.delete_prefix("mailto:")
      end
    end
  end
end
