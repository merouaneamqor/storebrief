class OidcController < ApplicationController
  include Authentication
  skip_before_action :require_login
  skip_before_action :bind_session_tenant
  skip_before_action :require_privacy_acceptance
  before_action :load_provider
  rate_limit to: 30, within: 1.minute, only: :start

  def start
    @tenant.oidc_login_attempts.where("expires_at < ?", 1.day.ago).limit(1000).delete_all
    state, nonce, verifier, browser = Array.new(4) { SecureRandom.urlsafe_base64(32) }
    session[:oidc_browser] = browser
    attempt = @tenant.oidc_login_attempts.create!(
      state_digest: OidcLoginAttempt.digest(state), nonce_digest: OidcLoginAttempt.digest(nonce),
      browser_digest: OidcLoginAttempt.digest(browser), expires_at: 5.minutes.from_now,
      code_verifier_ciphertext: Oidc::Secrets.encrypt(verifier, purpose: "oidc pkce"),
      issuer: @setting.issuer, client_id: @setting.client_id,
      redirect_uri: oidc_callback_url(tenant_slug: @tenant.slug))
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    redirect_to Oidc::Provider.new(@setting).authorization_url(attempt: attempt, state: state, nonce: nonce, challenge: challenge), allow_other_host: true
  rescue Oidc::Error
    failed_login
  end

  def callback
    state = params[:state]
    raise Oidc::Error unless state.is_a?(String) && state.bytesize.between?(32, 128)

    attempt = @tenant.oidc_login_attempts.find_by!(state_digest: OidcLoginAttempt.digest(state))
    attempt.consume!(browser: session[:oidc_browser], issuer: @setting.issuer, client_id: @setting.client_id)
    @login_return_path = take_login_destination
    reset_session
    code = params[:code]
    raise Oidc::Error if params[:error].present? || !code.is_a?(String) || code.blank? || code.bytesize > 4096

    claims = Oidc::Provider.new(@setting).claims(code: code, attempt: attempt)
    user = Oidc::Provisioner.new(@setting, claims).call
    establish_session!(user, return_to: @login_return_path)
  rescue Oidc::Error, ActiveRecord::RecordNotFound
    failed_login
  end

  private

  def load_provider
    @tenant = Tenant.find_by(slug: params[:tenant_slug].to_s)
    app_host = ENV.fetch("APP_HOST", "localhost")
    allowed_host = @tenant && [ app_host, "#{@tenant.slug}.#{app_host}" ].include?(request.host)
    if !allowed_host || (host_tenant? && current_tenant.id != @tenant.id) || !@tenant.oidc_sso_enabled?
      failed_login
      return
    end
    @setting = @tenant.oidc_setting
  end

  def failed_login
    remember_login_destination(@login_return_path) if @login_return_path
    redirect_to login_path(tenant_slug: @tenant&.slug), alert: t("auth.sso_failed")
  end
end
