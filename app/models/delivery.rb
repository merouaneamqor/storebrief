class Delivery < ApplicationRecord
  STATUSES = %w[pending completed read].freeze

  belongs_to :communication
  belongs_to :org_unit

  validates :status, inclusion: { in: STATUSES }
  validates :org_unit_id, uniqueness: { scope: :communication_id }

  scope :pending, -> { where(status: "pending") }
  scope :for_store, ->(org_unit) { where(org_unit_id: org_unit.id) }

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_read!
    update!(status: "read", completed_at: Time.current)
  end

  def pending?
    status == "pending"
  end
end
