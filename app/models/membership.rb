class Membership < ApplicationRecord
  ROLES = %w[hq area store].freeze

  # Explicit permission matrix. Compose / org / billing / playbooks stay HQ-only.
  # Area may monitor, escalate (coach verdicts), plan visits, and read scoped reports.
  CAPABILITIES = {
    "hq" => %i[
      compose monitor escalate visits playbooks billing manage_org reports verdicts admin approve
    ].freeze,
    "area" => %i[
      monitor escalate visits reports verdicts
    ].freeze,
    "store" => %i[
      execute inbox
    ].freeze
  }.freeze

  belongs_to :user
  belongs_to :org_unit

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :org_unit_id }
  validate :same_tenant

  def self.allows?(role, capability)
    CAPABILITIES.fetch(role.to_s, []).include?(capability.to_sym)
  end

  def allows?(capability)
    self.class.allows?(role, capability)
  end

  private

  def same_tenant
    return if user.blank? || org_unit.blank?
    return if user.tenant_id == org_unit.tenant_id

    errors.add(:base, "user and org unit must belong to the same tenant")
  end
end
