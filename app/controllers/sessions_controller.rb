class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]
  skip_before_action :set_current_tenant, only: %i[new create]

  def new
    redirect_to root_path if current_user
  end

  def create
    tenant = Tenant.find_by(slug: params[:tenant_slug].to_s.strip.downcase)
    user = tenant&.users&.find_by(email: params[:email].to_s.downcase.strip)

    if user&.authenticate(params[:password])
      reset_session
      session[:user_id] = user.id
      session[:locale] = user.locale
      redirect_to root_path, notice: t("auth.signed_in", tenant: user.tenant.name)
    else
      flash.now[:alert] = t("auth.invalid")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("auth.signed_out")
  end
end
