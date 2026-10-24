# Confidential default price per store per month. Only read through Vazivo::Pricing
# or Super Admin screens. Existing quotations keep their own unit_price snapshot.
class PricingPlan < ApplicationRecord
  KEYS = %w[starter business enterprise grand_compte].freeze

  has_many :versions, class_name: "PricingPlanVersion", dependent: :restrict_with_error
  has_many :quotations, dependent: :restrict_with_error

  validates :key, inclusion: { in: KEYS }, uniqueness: true
  validates :currency, inclusion: { in: %w[MAD] }
  validates :unit_price, numericality: { greater_than: 0, less_than: 100_000 }, allow_nil: true
  validates :max_stores, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_discount_percent, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :volume_tiers_well_formed

  after_save :record_version_and_audit, if: :saved_changes?

  scope :ordered, -> { order(:position) }

  def custom_quotation?
    unit_price.nil?
  end

  private

  def volume_tiers_well_formed
    ok = volume_tiers.is_a?(Array) && volume_tiers.all? do |t|
      t.is_a?(Hash) && t["min_stores"].to_i.positive? && t["discount_percent"].to_d.between?(0, max_discount_percent)
    end
    errors.add(:volume_tiers, :invalid) unless ok
  end

  def record_version_and_audit
    if saved_change_to_unit_price? || saved_change_to_currency? || saved_change_to_active_for_sales?
      versions.create!(unit_price: unit_price, currency: currency, active_for_sales: active_for_sales,
                       changed_by_id: Current.user&.id)
    end
    PricingAuditLog.record!(Current.user, saved_change_to_id? ? "create" : "update", self,
                            saved_changes.except("updated_at"))
  end
end
