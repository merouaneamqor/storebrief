# frozen_string_literal: true

class PrivacyPreferencesController < ApplicationController
  skip_before_action :require_privacy_acceptance

  def show
  end

  def update
    if accepting_notice?
      current_user.update!(privacy_notice_accepted_at: Time.current)
    end

    current_user.update!(preference_params)

    redirect_to privacy_preferences_path, notice: t("privacy.preferences.saved")
  end

  def data_request
    PrivacyMailer.data_subject_request(
      user: current_user,
      request_type: params.require(:request_type),
      details: params[:details].to_s.strip
    ).deliver_now

    redirect_to privacy_preferences_path, notice: t("privacy.preferences.data_request_sent")
  rescue ActionMailer::MailDeliveryError => e
    Rails.logger.error("[privacy] data request mail failed: #{e.class}: #{e.message}")
    redirect_to privacy_preferences_path, alert: t("privacy.preferences.data_request_failed")
  end

  private

  def accepting_notice?
    params[:accept_privacy_notice] == "1"
  end

  def preference_params
    permitted = params.fetch(:user, {}).permit(:operational_email_opt_out, :whatsapp_alerts_consent)
    attrs = {}
    attrs[:operational_email_opt_out] = permitted[:operational_email_opt_out] == "1" if permitted.key?(:operational_email_opt_out)

    if permitted.key?(:whatsapp_alerts_consent)
      attrs[:whatsapp_alerts_consent_at] = permitted[:whatsapp_alerts_consent] == "1" ? Time.current : nil
    end

    attrs
  end
end
