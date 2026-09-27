class Membership < ApplicationRecord
  ROLES = %w[hq store].freeze

  belongs_to :user
  belongs_to :org_unit

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :org_unit_id }
  validate :same_tenant

  private

  def same_tenant
    return if user.blank? || org_unit.blank?
    return if user.tenant_id == org_unit.tenant_id

    errors.add(:base, "user and org unit must belong to the same tenant")
  end
end
