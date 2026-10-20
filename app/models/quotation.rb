# Customer-specific quotation. Super Admin only; unit_price is a snapshot so later
# default price changes never reprice it. Drafts stay private; issuing is explicit.
class Quotation < ApplicationRecord
  STATUSES = %w[draft issued void].freeze

  belongs_to :pricing_plan
  belongs_to :created_by, class_name: "User", optional: true

  validates :customer_name, presence: true
  validates :customer_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validates :store_count, numericality: { only_integer: true, greater_than: 0, less_than: 100_000 }
  validates :unit_price, numericality: { greater_than: 0, less_than: 100_000 }
  validates :discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :discount_within_approved_limit
  validate :valid_until_not_past, on: :create
  validate :immutable_once_issued, on: :update

  before_validation :set_defaults, on: :create
  after_save :audit

  def monthly_total
    Vazivo::Pricing.monthly_total(store_count, unit_price, discount_percent)
  end

  def annual_total
    Vazivo::Pricing.annual_total(store_count, unit_price, discount_percent)
  end

  def issue!
    update!(status: "issued", issued_at: Time.current)
  end

  def void!
    update!(status: "void")
  end

  private

  def set_defaults
    self.currency = pricing_plan&.currency || "MAD"
    self.unit_price = pricing_plan&.unit_price if unit_price.blank?
    self.reference ||= "Q-#{Time.current.strftime('%y%m%d')}-#{SecureRandom.hex(3).upcase}"
  end

  def discount_within_approved_limit
    return unless pricing_plan && discount_percent.to_d > pricing_plan.max_discount_percent

    errors.add(:discount_percent, :less_than_or_equal_to, count: pricing_plan.max_discount_percent)
  end

  def valid_until_not_past
    errors.add(:valid_until, :invalid) if valid_until && valid_until < Date.current
  end

  def immutable_once_issued
    return unless status_was == "issued"

    locked = changed - %w[status updated_at]
    errors.add(:base, "Issued quotations cannot be edited") if locked.any?
    errors.add(:status, :invalid) unless %w[issued void].include?(status)
  end

  def audit
    return unless saved_changes?

    PricingAuditLog.record!(Current.user, saved_change_to_id? ? "create" : "update", self,
                            saved_changes.except("updated_at"))
  end
end
