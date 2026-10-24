class ChecklistDeliveryEvent < ApplicationRecord
  belongs_to :tenant
  belongs_to :checklist_delivery
  belongs_to :actor, class_name: "User", optional: true
  validates :kind, inclusion: { in: %w[status verdict comment] }
  validate do
    errors.add(:tenant, :invalid) unless checklist_delivery&.checklist&.tenant_id == tenant_id
    errors.add(:actor, :invalid) if actor && actor.tenant_id != tenant_id
  end

  def readonly?
    persisted?
  end
end
