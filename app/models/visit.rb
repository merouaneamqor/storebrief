class Visit < ApplicationRecord
  STATUSES = %w[planned in_progress completed cancelled].freeze

  belongs_to :tenant
  belongs_to :org_unit
  belongs_to :auditor, class_name: "User"
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :audit_template, optional: true

  validates :planned_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :org_unit_is_tenant_store
  validate :auditor_is_eligible
  validate :template_same_tenant

  scope :upcoming_first, -> { order(:planned_at, :id) }
  scope :with_status, ->(status) { where(status: status) if STATUSES.include?(status.to_s) }
  scope :active, -> { where.not(status: "cancelled") }

  # HQ and area users can audit; store users cannot.
  def self.auditor_candidates(tenant)
    tenant.users
          .where(super_admin: false)
          .where(id: Membership.where(role: %w[hq area]).select(:user_id))
          .order(:name)
  end

  def planned?
    status == "planned"
  end

  def cancelled?
    status == "cancelled"
  end

  def editable?
    planned?
  end

  def cancellable?
    planned? || status == "in_progress"
  end

  def cancel!(reason: nil)
    raise ArgumentError, I18n.t("morocco.visits.cannot_cancel") unless cancellable?

    update!(status: "cancelled", cancelled_at: Time.current, cancel_reason: reason.presence)
  end

  private

  def org_unit_is_tenant_store
    return if org_unit.blank?
    return if org_unit.tenant_id == tenant_id && org_unit.store?

    errors.add(:org_unit, :invalid)
  end

  def template_same_tenant
    return if audit_template.blank?
    return if audit_template.tenant_id == tenant_id

    errors.add(:audit_template, :invalid)
  end

  def auditor_is_eligible
    return if auditor.blank?
    return if auditor.tenant_id == tenant_id && auditor.memberships.exists?(role: %w[hq area])

    errors.add(:auditor, :invalid)
  end
end
