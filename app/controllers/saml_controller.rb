# frozen_string_literal: true

class SamlController < ApplicationController
  include Authentication

  skip_before_action :require_login
  skip_before_action :bind_session_tenant
  skip_before_action :verify_authenticity_token, only: :acs

  before_action :load_tenant
  before_action :require_saml_ready, only: %i[sso acs]

  def sso
    settings = Saml::SettingsBuilder.for(@tenant, request: request)
    redirect_to ::OneLogin::RubySaml::Authrequest.new.create(settings), allow_other_host: true
  end

  def acs
    settings = Saml::SettingsBuilder.for(@tenant, request: request)
    response = ::OneLogin::RubySaml::Response.new(params[:SAMLResponse], settings: settings)

    unless response.is_valid?
      redirect_to login_path(tenant_slug: @tenant.slug), alert: t("auth.sso_failed")
      return
    end

    email = extract_email(response)
    if email.blank?
      redirect_to login_path(tenant_slug: @tenant.slug), alert: t("auth.sso_failed")
      return
    end

    user = @tenant.users.find_by(email: email.downcase.strip)
    if user.nil? || user.super_admin?
      redirect_to login_path(tenant_slug: @tenant.slug), alert: t("auth.sso_user_not_found")
      return
    end

    establish_session!(user)
  end

  def metadata
    unless @tenant
      head :not_found
      return
    end

    builder = Saml::SettingsBuilder.urls_for(@tenant, request: request)
    settings = builder.sp_only_settings
    meta = ::OneLogin::RubySaml::Metadata.new
    render xml: meta.generate(settings), content_type: "application/samlmetadata+xml"
  end

  private

  def load_tenant
    @tenant = Tenant.find_by(slug: params[:tenant_slug].to_s.downcase)
    return if @tenant

    redirect_to login_path, alert: t("auth.sso_unknown_tenant")
  end

  def require_saml_ready
    return if performed?
    return if @tenant&.saml_sso_enabled?

    redirect_to login_path(tenant_slug: @tenant&.slug), alert: t("auth.sso_not_configured")
  end

  def extract_email(response)
    setting = @tenant.saml_setting
    attrs = response.attributes

    if setting.email_attribute.present?
      value = attrs[setting.email_attribute]
      return Array(value).first.to_s if value.present?
    end

    %w[email mail Email http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress].each do |key|
      value = attrs[key]
      return Array(value).first.to_s if value.present?
    end

    response.nameid.to_s
  end
end
