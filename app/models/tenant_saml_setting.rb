# frozen_string_literal: true

class TenantSamlSetting < ApplicationRecord
  belongs_to :tenant

  validates :idp_entity_id, :idp_sso_target_url, :idp_cert, presence: true, if: :enabled?
  validates :idp_sso_target_url, format: { with: /\Ahttps?:\/\//i }, allow_blank: true
  validate :certificate_looks_valid, if: -> { enabled? && idp_cert.present? }

  def ready?
    enabled? && idp_entity_id.present? && idp_sso_target_url.present? && idp_cert.present?
  end

  private

  def certificate_looks_valid
    text = idp_cert.to_s
    return if text.include?("BEGIN CERTIFICATE") || text.match?(/\A[A-Za-z0-9\/+\s=]+\z/)

    errors.add(:idp_cert, "must be a PEM certificate or base64-encoded certificate body")
  end
end
