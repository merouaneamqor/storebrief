class TicketEvent < ApplicationRecord
  belongs_to :incident_ticket
  belongs_to :actor, class_name: "User"
  validates :kind, inclusion: { in: %w[created status assignee] }

  validate do
    errors.add(:actor, :invalid) if actor && incident_ticket && actor.tenant_id != incident_ticket.tenant_id
  end

  def readonly?
    persisted?
  end
end
