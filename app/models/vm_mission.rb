class VmMission < ApplicationRecord
  include Bilingual

  STATUSES = %w[open closed].freeze
  ATTACHMENT_TYPES = %w[
    application/pdf
    image/png
    image/jpeg
    image/jpg
    image/webp
  ].freeze
  ATTACHMENT_MAX_BYTES = 10.megabytes
  ATTACHMENT_MAX_COUNT = 10

  belongs_to :tenant
  belongs_to :created_by, class_name: "User", optional: true
  has_many :vm_mission_targets, dependent: :destroy
  has_many :org_units, through: :vm_mission_targets
  has_many_attached :attachments

  validates :title_fr, :instructions_fr, :deadline_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :version_label, length: { maximum: 80 }, allow_blank: true
  validate :at_least_one_target
  validate :targets_must_be_tenant_stores
  validate :acceptable_attachments

  bilingual_fields :title, :instructions

  scope :deadline_first, -> { order(:deadline_on, :id) }
  scope :with_status, ->(status) { where(status: status) if STATUSES.include?(status.to_s) }
  scope :open_missions, -> { where(status: "open") }
  scope :for_store, ->(org_unit) {
    joins(:vm_mission_targets).where(vm_mission_targets: { org_unit_id: org_unit.id }).distinct
  }

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def overdue?
    open? && deadline_on.present? && deadline_on < Date.current
  end

  def attachments?
    attachments.attached?
  end

  def versioned?
    version_label.present?
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

  def acceptable_attachments
    return unless attachments.attached?

    if attachments.count > ATTACHMENT_MAX_COUNT
      errors.add(:attachments, I18n.t("morocco.vm_missions.attachments_too_many", count: ATTACHMENT_MAX_COUNT))
    end

    attachments.each do |file|
      next unless file.blob

      unless ATTACHMENT_TYPES.include?(file.content_type)
        errors.add(:attachments, I18n.t("morocco.vm_missions.attachments_invalid"))
        break
      end

      if file.byte_size.to_i > ATTACHMENT_MAX_BYTES
        errors.add(:attachments, I18n.t("morocco.vm_missions.attachments_too_large"))
        break
      end
    end
  end
end
