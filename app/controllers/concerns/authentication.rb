# frozen_string_literal: true

module Authentication
  extend ActiveSupport::Concern

  private

  def establish_session!(user, acting_tenant: nil)
    home = user.tenant
    acting = acting_tenant || home
    reset_session
    session[:user_id] = user.id
    session[:locale] = user.locale
    session[:acting_tenant_id] = acting.id if user.super_admin?
    redirect_to app_root_path, notice: t("auth.signed_in", tenant: (user.super_admin? ? acting : home).name)
  end
end
