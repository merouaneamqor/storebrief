class TicketCategory < ApplicationRecord
  belongs_to :tenant
  has_many :incident_tickets, dependent: :restrict_with_error
  validates :name, :department, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :tenant_id }
  validates :sla_hours, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 8760 }
end
