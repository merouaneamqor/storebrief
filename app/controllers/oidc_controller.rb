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
    state = params[:state].to_s
    raise Oidc::Error unless state.bytesize.between?(32, 128)

    attempt = @tenant.oidc_login_attempts.find_by!(state_digest: OidcLoginAttempt.digest(state))
    attempt.consume!(browser: session.delete(:oidc_browser), issuer: @setting.issuer, client_id: @setting.client_id)
    reset_session
    raise Oidc::Error if params[:error].present? || params[:code].to_s.blank? || params[:code].to_s.bytesize > 4096

    claims = Oidc::Provider.new(@setting).claims(code: params[:code].to_s, attempt: attempt)
    user = Oidc::Provisioner.new(@setting, claims).call
    establish_session!(user)
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
    redirect_to login_path(tenant_slug: @tenant&.slug), alert: t("auth.sso_failed")
  end
end
