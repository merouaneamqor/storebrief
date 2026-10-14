class ChecklistDelivery < ApplicationRecord
  include Vazivo::Execution

  STATUSES = %w[pending completed].freeze

  belongs_to :checklist
  belongs_to :org_unit
  belongs_to :assignee, class_name: "User", optional: true
  has_many :checklist_item_responses, dependent: :destroy
  has_many :escalation_events, as: :subject, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :org_unit_id, uniqueness: { scope: :checklist_id }

  scope :pending, -> { where(status: "pending") }
  scope :for_store, ->(org_unit) { where(org_unit_id: org_unit.id) }

  def pending?
    status == "pending"
  end

  def completed?
    status == "completed"
  end

  def ready_to_complete?
    responses = checklist_item_responses.includes(photo_attachment: :blob).index_by(&:checklist_item_id)

    checklist.checklist_items.all? do |item|
      response = responses[item.id]
      next false unless response&.completed?
      next false if item.requires_photo? && !response.evidence_attached?

      true
    end
  end

  def missing_required_evidence?
    responses = checklist_item_responses.includes(photo_attachment: :blob).index_by(&:checklist_item_id)

    checklist.checklist_items.any? do |item|
      next false unless item.requires_photo?

      response = responses[item.id]
      !response&.evidence_attached?
    end
  end

  def complete_if_ready!
    return false unless pending?
    return false unless ready_to_complete?

    update!(status: "completed", completed_at: Time.current)
    true
  end
end
