# frozen_string_literal: true

class PrivacyMailer < ApplicationMailer
  def data_subject_request(user:, request_type:, details:)
    @user = user
    @tenant = user.tenant
    @request_type = request_type
    @details = details

    mail(
      to: Vazivo::Privacy.contact_email,
      subject: "[Vazivo] Demande droits Loi 09-08 — #{request_type} (#{@user.email})"
    )
  end
end
