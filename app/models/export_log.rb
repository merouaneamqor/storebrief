# Append-only metadata. Exported row content never belongs in the audit log.
class ExportLog < ApplicationRecord
  belongs_to :tenant
  belongs_to :actor, class_name: "User", optional: true

  validates :source, presence: true
  validates :output_format, inclusion: { in: %w[csv xlsx html] }
  validates :row_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :actor_belongs_to_tenant

  def readonly?
    persisted?
  end

  private

  def actor_belongs_to_tenant
    errors.add(:actor, :invalid) if actor && actor.tenant_id != tenant_id
  end
end
