# Per-tenant outbound email: their SMTP, or Vazivo platform SMTP (billed).
class TenantMailSetting < ApplicationRecord
  AUTH_METHODS = %w[plain login cram_md5].freeze

  belongs_to :tenant

  validates :smtp_port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }
  validates :smtp_authentication, inclusion: { in: AUTH_METHODS }
  validates :from_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validate :tenant_smtp_complete_when_not_platform

  def smtp_password=(value)
    super if value.present?
  end

  def configured_tenant_smtp?
    !use_platform? && smtp_address.present? && from_email.present?
  end

  def delivery_mode
    configured_tenant_smtp? ? :tenant_smtp : :platform_billed
  end

  def from_address
    email = from_email.presence || (configured_tenant_smtp? ? nil : PlatformMail.from_email)
    return PlatformMail.from_address if email.blank?

    name = from_name.presence || tenant.display_brand_name
    Mail::Address.new.tap do |addr|
      addr.address = email
      addr.display_name = name
    end.format
  rescue StandardError
    email
  end

  def delivery_method_options
    if configured_tenant_smtp?
      {
        address: smtp_address,
        port: smtp_port,
        domain: smtp_domain.presence,
        user_name: smtp_username.presence,
        password: smtp_password.presence,
        authentication: smtp_authentication.to_sym,
        enable_starttls_auto: smtp_enable_starttls_auto
      }.compact
    else
      PlatformMail.smtp_settings
    end
  end

  private

  def tenant_smtp_complete_when_not_platform
    return if use_platform?

    errors.add(:smtp_address, :blank) if smtp_address.blank?
    errors.add(:from_email, :blank) if from_email.blank?
  end
end
