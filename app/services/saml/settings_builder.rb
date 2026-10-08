# frozen_string_literal: true

module Saml
  class SettingsBuilder
    def self.for(tenant, request: nil)
      new(tenant, request: request).build
    end

    def self.urls_for(tenant, request: nil)
      new(tenant, request: request)
    end

    def initialize(tenant, request: nil)
      @tenant = tenant
      @setting = tenant.saml_setting
      @request = request
    end

    def build
      raise ArgumentError, "SAML is not configured for this tenant" unless @setting&.ready?

      settings = ::OneLogin::RubySaml::Settings.new
      apply_sp_settings(settings)

      settings.idp_entity_id = @setting.idp_entity_id
      settings.idp_sso_target_url = @setting.idp_sso_target_url
      settings.idp_cert = normalize_cert(@setting.idp_cert)

      settings.security[:authn_requests_signed] = false
      settings.security[:logout_requests_signed] = false
      settings.security[:logout_responses_signed] = false
      settings.security[:want_assertions_signed] = true
      settings.security[:metadata_signed] = false
      settings.security[:digest_method] = ::XMLSecurity::Document::SHA256
      settings.security[:signature_method] = ::XMLSecurity::Document::RSA_SHA256

      settings
    end

    def sp_only_settings
      settings = ::OneLogin::RubySaml::Settings.new
      apply_sp_settings(settings)
      settings.security[:want_assertions_signed] = true
      settings
    end

    def sp_entity_id
      "#{base_url}/saml/#{@tenant.slug}"
    end

    def acs_url
      "#{base_url}/saml/#{@tenant.slug}/acs"
    end

    def metadata_url
      "#{base_url}/saml/#{@tenant.slug}/metadata"
    end

    private

    def apply_sp_settings(settings)
      settings.sp_entity_id = sp_entity_id
      settings.assertion_consumer_service_url = acs_url
      settings.assertion_consumer_service_binding = "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
      settings.name_identifier_format = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    end

    def base_url
      if (explicit = ENV["APP_URL"].presence)
        return explicit.delete_suffix("/")
      end

      host = ENV.fetch("APP_HOST", "localhost")
      if @request && !Rails.env.production?
        scheme = @request.ssl? ? "https" : "http"
        port = @request.port
        default_port = @request.ssl? ? 443 : 80
        port_part = port == default_port ? "" : ":#{port}"
        return "#{scheme}://#{host}#{port_part}"
      end

      scheme = Rails.env.production? ? "https" : "http"
      if host == "localhost" && !Rails.env.production?
        "#{scheme}://#{host}:3000"
      else
        "#{scheme}://#{host}"
      end
    end

    def normalize_cert(cert)
      text = cert.to_s.strip
      return text if text.include?("BEGIN CERTIFICATE")

      body = text.gsub(/\s+/, "")
      "-----BEGIN CERTIFICATE-----\n#{body.scan(/.{1,64}/).join("\n")}\n-----END CERTIFICATE-----"
    end
  end
end
