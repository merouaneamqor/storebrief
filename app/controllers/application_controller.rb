class ApplicationController < ActionController::Base
  RESERVED_SUBDOMAINS = %w[www admin mail api].freeze

  helper_method :current_user, :current_tenant, :acting_tenant, :hq_user?, :super_admin?, :rtl?, :apex_request?, :host_tenant?, :tenant_feature?

  before_action :redirect_www
  before_action :set_tenant_from_host
  before_action :require_login, unless: :active_admin_controller?
  before_action :bind_session_tenant
  before_action :set_locale

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_tenant
    Current.tenant
  end

  def acting_tenant
    Current.tenant
  end

  def hq_user?
    super_admin? || current_user&.hq?
  end

  def super_admin?
    current_user&.super_admin?
  end

  def rtl?
    I18n.locale.to_s == "ar"
  end

  def app_host
    ENV.fetch("APP_HOST", "localhost")
  end

  def app_tld_length
    default = app_host == "localhost" ? "0" : "1"
    ENV.fetch("APP_TLD_LENGTH", default).to_i
  end

  def request_label
    request.subdomains(app_tld_length).first
  end

  def apex_request?
    !host_tenant?
  end

  def host_tenant?
    @tenant_from_host == true
  end

  def redirect_www
    return unless request_label == "www"

    redirect_to "#{request.protocol}#{app_host}#{request.port_string}#{request.fullpath}",
                allow_other_host: true,
                status: :moved_permanently
  end

  def set_tenant_from_host
    slug = request_label
    return if slug.blank? || RESERVED_SUBDOMAINS.include?(slug)

    tenant = Tenant.find_by(slug: slug)
    raise ActiveRecord::RecordNotFound, "Unknown tenant" unless tenant

    Current.tenant = tenant
    @tenant_from_host = true
  end

  def active_admin_controller?
    is_a?(ActiveAdmin::BaseController)
  end

  def require_login
    return if current_user

    redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
  end

  def bind_session_tenant
    return unless current_user

    if current_user.super_admin?
      Current.user = current_user
      Current.tenant = resolve_acting_tenant
      return
    end

    if host_tenant? && current_user.tenant_id != Current.tenant.id
      reset_session
      redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
      return
    end

    Current.user = current_user
    Current.tenant ||= current_user.tenant
  end

  def resolve_acting_tenant
    tenant = Tenant.find_by(id: session[:acting_tenant_id]) if session[:acting_tenant_id].present?
    tenant ||= host_tenant? ? Current.tenant : current_user.tenant
    session[:acting_tenant_id] = tenant.id
    tenant
  end

  def set_locale
    if active_admin_controller?
      I18n.locale = :en
      return
    end

    session[:locale] = params[:locale] if User::LOCALES.include?(params[:locale].to_s)

    locale = session[:locale].presence || current_user&.locale || "fr"
    locale = "fr" unless User::LOCALES.include?(locale.to_s)
    I18n.locale = locale
  end

  def require_hq
    return if hq_user?

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def authenticate_hq_admin!
    return if current_user&.hq? || current_user&.super_admin?

    if current_user
      redirect_to app_root_path, alert: t("auth.hq_required")
    else
      redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
    end
  end

  def require_super_admin
    return if super_admin?

    redirect_to app_root_path, alert: t("auth.super_admin_required")
  end

  def tenant_feature?(key)
    Current.tenant&.feature?(key)
  end

  def require_feature!(key)
    return if tenant_feature?(key)

    redirect_to app_root_path, alert: t("auth.feature_disabled")
  end

  def tenant_scope
    Current.tenant
  end
end
