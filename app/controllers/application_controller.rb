class ApplicationController < ActionController::Base
  helper_method :current_user, :current_tenant, :hq_user?

  before_action :require_login
  before_action :set_current_tenant

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

  def require_login
    return if current_user

    redirect_to login_path, alert: "Please sign in to continue."
  end

  def set_current_tenant
    return unless current_user

    Current.user = current_user
    Current.tenant = current_user.tenant
  end

  def require_hq
    return if hq_user?

    redirect_to root_path, alert: "HQ access required."
  end

  def tenant_scope
    Current.tenant
  end
end
