class DemoRequest < ApplicationRecord
  LOCALES = %w[fr en es ar].freeze
  STATUSES = %w[new contacted closed].freeze

  validates :name, :company, presence: true
  validates :preferred_locale, inclusion: { in: LOCALES }
  validates :status, inclusion: { in: STATUSES }
  validate :email_or_phone_present
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :store_count, numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  private

  def email_or_phone_present
    return if email.present? || phone.present?

    errors.add(:base, :contact_required)
  end
end
