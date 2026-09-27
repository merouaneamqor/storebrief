class ApplicationController < ActionController::Base
  helper_method :current_user, :current_tenant, :hq_user?, :rtl?

  before_action :require_login, unless: :active_admin_controller?
  before_action :set_current_tenant
  before_action :set_locale

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def current_tenant
    Current.tenant
  end

  def hq_user?
    current_user&.hq?
  end

  def rtl?
    I18n.locale.to_s == "ar"
  end

  def active_admin_controller?
    is_a?(ActiveAdmin::BaseController)
  end

  def require_login
    return if current_user

    redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
  end

  def set_current_tenant
    return unless current_user

    Current.user = current_user
    Current.tenant = current_user.tenant
  end

  def set_locale
    if active_admin_controller?
      I18n.locale = :en
      return
    end

    locale = session[:locale].presence || current_user&.locale || "fr"
    locale = "fr" unless User::LOCALES.include?(locale.to_s)
    I18n.locale = locale
  end

  def require_hq
    return if hq_user?

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def authenticate_hq_admin!
    return if current_user&.hq?

    if current_user
      redirect_to app_root_path, alert: t("auth.hq_required")
    else
      redirect_to login_path, alert: I18n.t("auth.please_sign_in", locale: session[:locale].presence || :fr)
    end
  end

  def tenant_scope
    Current.tenant
  end
end
