class VmMissionTarget < ApplicationRecord
  belongs_to :vm_mission
  belongs_to :org_unit

  validates :org_unit_id, uniqueness: { scope: :vm_mission_id }
  validate :org_unit_is_tenant_store

  private

  def org_unit_is_tenant_store
    return if org_unit.blank? || vm_mission.blank?
    return if org_unit.tenant_id == vm_mission.tenant_id && org_unit.store?

    errors.add(:org_unit, :invalid)
  end
end
