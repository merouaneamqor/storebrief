class VmMission < ApplicationRecord
  include Bilingual

  STATUSES = %w[open closed].freeze

  belongs_to :tenant
  belongs_to :created_by, class_name: "User", optional: true
  has_many :vm_mission_targets, dependent: :destroy
  has_many :org_units, through: :vm_mission_targets

  validates :title_fr, :instructions_fr, :deadline_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :at_least_one_target
  validate :targets_must_be_tenant_stores

  bilingual_fields :title, :instructions

  scope :deadline_first, -> { order(:deadline_on, :id) }
  scope :with_status, ->(status) { where(status: status) if STATUSES.include?(status.to_s) }
  scope :open_missions, -> { where(status: "open") }

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def overdue?
    open? && deadline_on.present? && deadline_on < Date.current
  end

  # Replace target stores with tenant-scoped store ids only.
  def sync_targets!(org_unit_ids)
    ids = Array(org_unit_ids).compact_blank.map(&:to_i).uniq
    stores = tenant.org_units.stores.where(id: ids)
    self.org_units = stores.to_a
  end

  private

  def at_least_one_target
    errors.add(:org_units, :blank) if org_units.empty?
  end

  def targets_must_be_tenant_stores
    return if org_units.empty?

    invalid = org_units.reject { |unit| unit.tenant_id == tenant_id && unit.store? }
    errors.add(:org_units, :invalid) if invalid.any?
  end
end
