class Membership < ApplicationRecord
  ROLES = %w[hq area store].freeze

  # Explicit permission matrix. Compose / org / billing / playbooks stay HQ-only.
  # Area may monitor, escalate (coach verdicts), plan visits, and read scoped reports.
  CAPABILITIES = {
    "hq" => %i[
      compose monitor escalate visits playbooks billing manage_org reports verdicts admin approve communities manage_communities
    ].freeze,
    "area" => %i[
      monitor escalate visits reports verdicts communities
    ].freeze,
    "store" => %i[
      execute inbox communities
    ].freeze
  }.freeze

  belongs_to :user
  belongs_to :org_unit
  belongs_to :tenant_role, optional: true

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :org_unit_id }
  validate :same_tenant
  validate :role_same_tenant_and_base
  validate :custom_hq_cannot_become_admin

  def self.allows?(role, capability)
    CAPABILITIES.fetch(role.to_s, []).include?(capability.to_sym)
  end

  def allows?(capability)
    tenant_role ? tenant_role.allows?(capability) : self.class.allows?(role, capability)
  end

  # Built-in HQ remains tenant-wide; custom roles are anchored to their unit.
  def covers?(unit)
    return false unless unit && unit.tenant_id == user.tenant_id && org_unit.tenant_id == user.tenant_id
    return true if role == "hq" && tenant_role_id.nil?

    seen = []
    cursor = unit
    while cursor && cursor.tenant_id == user.tenant_id && !seen.include?(cursor.id)
      return true if cursor.id == org_unit_id

      seen << cursor.id
      cursor = cursor.parent
    end
    false
  end

  def tenant_wide?
    return true if role == "hq" && tenant_role_id.nil?

    user.tenant.org_units.all? { |unit| covers?(unit) }
  end

  def workflow_role
    role == "hq" && tenant_role && !tenant_wide? ? "area" : role
  end

  private

  def role_same_tenant_and_base
    return unless tenant_role
    return if tenant_role.tenant_id == user&.tenant_id && tenant_role.base_role == role

    errors.add(:tenant_role, :invalid)
  end

  def custom_hq_cannot_become_admin
    if persisted? && tenant_role_id_in_database.present? && tenant_role_id.nil? && role == "hq"
      errors.add(:tenant_role, :invalid)
    end
  end

  def same_tenant
    return if user.blank? || org_unit.blank?
    return if user.tenant_id == org_unit.tenant_id

    errors.add(:base, "user and org unit must belong to the same tenant")
  end
end
