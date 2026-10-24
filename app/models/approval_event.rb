# Append-only audit trail for HQ approval transitions (before anything reaches stores).
class ApprovalEvent < ApplicationRecord
  KINDS = %w[submitted approved rejected deployed].freeze

  belongs_to :tenant
  belongs_to :subject, polymorphic: true
  belongs_to :actor, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }

  def readonly?
    persisted?
  end
end
