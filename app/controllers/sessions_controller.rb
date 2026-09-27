class SessionsController < ApplicationController
  layout "marketing"

  skip_before_action :require_login, only: %i[new create]
  skip_before_action :bind_session_tenant, only: %i[new create]

  def new
    return unless current_user
    return redirect_to(app_root_path) if current_user.super_admin?
    return redirect_to(app_root_path) if !host_tenant? || current_user.tenant_id == Current.tenant.id
  end

  def create
    email = params[:email].to_s.downcase.strip
    slug = params[:tenant_slug].to_s.strip
    tenant = login_tenant
    if !host_tenant? && slug.present? && tenant.nil?
      flash.now[:alert] = t("auth.invalid")
      render :new, status: :unprocessable_entity
      return
    end

    user = tenant&.users&.find_by(email: email)
    user ||= User.super_admins.find_by(email: email)

    if user&.authenticate(params[:password]) && tenant_matches_host?(user)
      home = user.tenant
      acting = acting_tenant_for(user, tenant)
      reset_session
      session[:user_id] = user.id
      session[:locale] = user.locale
      session[:acting_tenant_id] = acting.id if user.super_admin?
      redirect_to app_root_path, notice: t("auth.signed_in", tenant: (user.super_admin? ? acting : home).name)
    else
      flash.now[:alert] = t("auth.invalid")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("auth.signed_out")
  end

  private

  def login_tenant
    return Current.tenant if host_tenant?

    slug = params[:tenant_slug].to_s.strip.downcase
    return if slug.blank?

    Tenant.find_by(slug: slug)
  end

  def tenant_matches_host?(user)
    return true if user.super_admin?
    return true unless host_tenant?

    user.tenant_id == Current.tenant.id
  end

  def acting_tenant_for(user, tenant)
    return Current.tenant if host_tenant?
    return tenant if tenant && user.super_admin?

    user.tenant
  end
end
