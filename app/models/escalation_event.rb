class EscalationEvent < ApplicationRecord
  ROLES = %w[store_manager area_manager hq].freeze

  belongs_to :tenant
  belongs_to :subject, polymorphic: true

  validates :level, inclusion: { in: 1..3 }
  validates :notified_role, inclusion: { in: ROLES }
end
