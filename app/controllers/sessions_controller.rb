class SessionsController < ApplicationController
  layout "marketing"

  skip_before_action :require_login, only: %i[new create]
  skip_before_action :bind_session_tenant, only: %i[new create]

  def new
    redirect_to app_root_path if current_user && (!host_tenant? || current_user.tenant_id == Current.tenant.id)
  end

  def create
    tenant = login_tenant
    user = tenant&.users&.find_by(email: params[:email].to_s.downcase.strip)

    if user&.authenticate(params[:password]) && tenant_matches_host?(user)
      reset_session
      session[:user_id] = user.id
      session[:locale] = user.locale
      redirect_to app_root_path, notice: t("auth.signed_in", tenant: user.tenant.name)
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

    Tenant.find_by(slug: params[:tenant_slug].to_s.strip.downcase)
  end

  def tenant_matches_host?(user)
    return true unless host_tenant?

    user.tenant_id == Current.tenant.id
  end
end
