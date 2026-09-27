class ChecklistDelivery < ApplicationRecord
  STATUSES = %w[pending completed].freeze

  belongs_to :checklist
  belongs_to :org_unit
  has_many :checklist_item_responses, dependent: :destroy

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

  def complete_if_ready!
    required = checklist.checklist_items
    responses = checklist_item_responses.index_by(&:checklist_item_id)

    ready = required.all? do |item|
      response = responses[item.id]
      next false unless response&.completed?
      next false if item.requires_photo? && !response.photo.attached?

      true
    end

    update!(status: "completed", completed_at: Time.current) if ready && pending?
  end
end
