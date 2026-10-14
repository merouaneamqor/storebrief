class VmMissionTarget < ApplicationRecord
  STATUSES = %w[pending pending_approval completed].freeze
  VERDICTS = %w[conforme improve non_conforme].freeze
  REJECT_VERDICT = "non_conforme".freeze
  PHOTO_TYPES = %w[image/png image/jpeg image/jpg image/webp].freeze
  PHOTO_MAX_BYTES = 10.megabytes

  belongs_to :vm_mission
  belongs_to :org_unit
  belongs_to :validated_by, class_name: "User", optional: true

  has_one_attached :photo_before
  has_one_attached :photo_after

  validates :org_unit_id, uniqueness: { scope: :vm_mission_id }
  validates :status, inclusion: { in: STATUSES }
  validates :verdict, inclusion: { in: VERDICTS }, allow_nil: true
  validate :org_unit_is_tenant_store
  validate :acceptable_photos

  def pending?
    status == "pending"
  end

  def pending_approval?
    status == "pending_approval"
  end

  def completed?
    status == "completed"
  end

  def proof_ready?
    photo_before.attached? && photo_after.attached?
  end

  def attach_photos!(before:, after:)
    photo_before.attach(before) if before.present?
    photo_after.attach(after) if after.present?
    self
  end

  def submit_for_review!
    raise ArgumentError, I18n.t("morocco.vm_missions.proof.mission_closed") if vm_mission.closed?
    raise ArgumentError, I18n.t("morocco.vm_missions.proof.already_submitted") if pending_approval?
    raise ArgumentError, I18n.t("morocco.vm_missions.proof.already_done") if completed?
    raise ArgumentError, I18n.t("morocco.proof_required") unless proof_ready?

    update!(
      status: "pending_approval",
      submitted_at: Time.current,
      verdict: nil,
      verdict_note: nil,
      validated_by: nil,
      validated_at: nil
    )
    self
  end

  def apply_verdict!(verdict, note:, by:)
    raise ArgumentError, I18n.t("morocco.vm_missions.proof.not_pending") unless pending_approval?
    raise ArgumentError, I18n.t("morocco.approval.note_required") if note.to_s.strip.blank?

    verdict = verdict.to_s
    raise ArgumentError, I18n.t("morocco.verdict.invalid") unless VERDICTS.include?(verdict)

    attrs = {
      verdict: verdict,
      verdict_note: note.to_s.strip,
      validated_by: by,
      validated_at: Time.current
    }

    if verdict == REJECT_VERDICT
      attrs.merge!(status: "pending", submitted_at: nil)
    else
      attrs.merge!(status: "completed")
    end

    update!(attrs)
    self
  end

  private

  def org_unit_is_tenant_store
    return if org_unit.blank? || vm_mission.blank?
    return if org_unit.tenant_id == vm_mission.tenant_id && org_unit.store?

    errors.add(:org_unit, :invalid)
  end

  def acceptable_photos
    [ photo_before, photo_after ].each do |photo|
      next unless photo.attached?
      next unless photo.blob

      unless PHOTO_TYPES.include?(photo.content_type)
        errors.add(:base, I18n.t("morocco.vm_missions.proof.photos_invalid"))
        break
      end

      if photo.byte_size.to_i > PHOTO_MAX_BYTES
        errors.add(:base, I18n.t("morocco.vm_missions.proof.photos_too_large"))
        break
      end
    end
  end
end
