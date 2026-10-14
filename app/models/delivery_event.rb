class DeliveryEvent < ApplicationRecord
  KINDS = %w[status awareness assignee verdict proof].freeze

  belongs_to :tenant
  belongs_to :delivery
  belongs_to :actor, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }

  # Append-only: never update or destroy history rows.
  def readonly?
    persisted?
  end
end
