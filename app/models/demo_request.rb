class DemoRequest < ApplicationRecord
  LOCALES = %w[fr en es ar].freeze
  STATUSES = %w[new contacted closed].freeze

  attr_accessor :privacy_consent

  validates :name, :company, presence: true
  validates :preferred_locale, inclusion: { in: LOCALES }
  validates :status, inclusion: { in: STATUSES }
  validate :email_or_phone_present
  validate :privacy_consent_given
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :store_count, numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  before_validation :stamp_privacy_consent

  private

  def stamp_privacy_consent
    return unless privacy_consent_granted?

    self.privacy_consent_at = Time.current
  end

  def privacy_consent_granted?
    privacy_consent == true || privacy_consent == "1" || privacy_consent == "true"
  end

  def privacy_consent_given
    return if privacy_consent_at.present? || privacy_consent_granted?

    errors.add(:base, :privacy_consent_required)
  end

  def email_or_phone_present
    return if email.present? || phone.present?

    errors.add(:base, :contact_required)
  end
end
