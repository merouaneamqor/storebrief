class OidcSettingsController < ApplicationController
  before_action :authenticate_hq_admin!

  def show
    @setting = tenant_scope.oidc_setting || tenant_scope.build_oidc_setting
    @identities = tenant_scope.oidc_identities.includes(:user).order(:id)
  end

  def update
    @setting = tenant_scope.oidc_setting || tenant_scope.build_oidc_setting
    if @setting.update(setting_params)
      redirect_to oidc_settings_path, notice: t("oidc.saved")
    else
      @identities = tenant_scope.oidc_identities.includes(:user).order(:id)
      render :show, status: :unprocessable_entity
    end
  end

  def link
    setting = tenant_scope.oidc_setting
    raise ActiveRecord::RecordNotFound unless setting&.ready?

    user = tenant_scope.users.where(super_admin: false).find(params[:user_id])
    identity = tenant_scope.oidc_identities.new(user: user, issuer: setting.issuer, subject: params[:subject].to_s, admin_linked: true)
    if identity.save
      redirect_to oidc_settings_path, notice: t("oidc.saved")
    else
      redirect_to oidc_settings_path, alert: t("oidc.invalid_link")
    end
  end

  def unlink
    tenant_scope.oidc_identities.find(params[:identity_id]).destroy!
    redirect_to oidc_settings_path, notice: t("oidc.saved")
  end

  private

  def setting_params
    params.require(:tenant_oidc_setting).permit(:enabled, :sso_enforced, :jit_enabled,
      :issuer, :client_id, :client_secret, :authorization_endpoint, :token_endpoint, :jwks_uri, :role_mappings_json)
  end
end
