class Community < ApplicationRecord
  include Bilingual
  bilingual_fields :title

  belongs_to :tenant
  belongs_to :org_unit, optional: true
  has_many :community_posts, dependent: :destroy

  validates :title_fr, presence: true, length: { maximum: 120 }
  validates :title_ar, length: { maximum: 120 }
  validates :audience_role, inclusion: { in: Membership::ROLES }, allow_blank: true
  validate :region_belongs_to_tenant

  # A membership must supply both the capability and the audience scope.
  # Community posts are deliberately shared with this audience, unlike delivery comments.
  def readable_by?(user)
    return false unless user&.tenant_id == tenant_id
    return true if manageable_by?(user)

    user.permission_memberships.any? do |membership|
      membership.allows?(:communities) &&
        (audience_role.blank? || membership.role == audience_role) &&
        (org_unit.nil? || membership.covers?(org_unit) || within_region?(membership.org_unit))
    end
  end

  def manageable_by?(user)
    user&.tenant_id == tenant_id && user.permission_memberships.any? do |membership|
      membership.allows?(:manage_communities) &&
        (org_unit ? membership.covers?(org_unit) : membership.tenant_wide?)
    end
  end

  private

  def within_region?(unit)
    seen = []
    while unit && unit.tenant_id == tenant_id && !seen.include?(unit.id)
      return true if unit.id == org_unit_id

      seen << unit.id
      unit = unit.parent
    end
    false
  end

  def region_belongs_to_tenant
    return if org_unit.nil? || (org_unit.tenant_id == tenant_id && org_unit.unit_type == "region")

    errors.add(:org_unit, :invalid)
  end
end
