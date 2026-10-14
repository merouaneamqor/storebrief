class ChecklistItemResponse < ApplicationRecord
  EVIDENCE_TYPES = %w[
    image/png
    image/jpeg
    image/jpg
    image/webp
    image/gif
    video/mp4
    video/webm
    video/quicktime
  ].freeze
  EVIDENCE_MAX_BYTES = 25.megabytes

  belongs_to :checklist_delivery
  belongs_to :checklist_item
  has_one :corrective_communication, class_name: "Communication",
                                     foreign_key: :source_checklist_item_response_id,
                                     inverse_of: :source_checklist_item_response,
                                     dependent: :nullify
  has_one_attached :photo

  validates :checklist_item_id, uniqueness: { scope: :checklist_delivery_id }
  validate :acceptable_evidence

  def completed?
    completed
  end

  def evidence_attached?
    photo.attached?
  end

  def evidence_video?
    evidence_attached? && photo.content_type.to_s.start_with?("video/")
  end

  def evidence_image?
    evidence_attached? && photo.content_type.to_s.start_with?("image/")
  end

  private

  def acceptable_evidence
    return unless photo.attached?
    return unless photo.blob

    unless EVIDENCE_TYPES.include?(photo.content_type)
      errors.add(:photo, I18n.t("checklists.evidence_invalid"))
    end

    if photo.byte_size.to_i > EVIDENCE_MAX_BYTES
      errors.add(:photo, I18n.t("checklists.evidence_invalid"))
    end
  end
end
