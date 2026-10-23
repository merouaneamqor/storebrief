# The legacy role selects workflow chrome; custom capabilities can only reduce it.
class TenantRole < ApplicationRecord
  belongs_to :tenant
  has_many :memberships, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 80 }, uniqueness: { scope: :tenant_id }
  validates :base_role, inclusion: { in: Membership::ROLES }
  validate :capability_subset
  validate :base_role_is_stable

  def capabilities=(values)
    super(Array(values).map(&:to_s).reject(&:blank?).uniq)
  end

  def allows?(capability)
    capabilities.include?(capability.to_s)
  end

  private

  def capability_subset
    allowed = Membership::CAPABILITIES.fetch(base_role.to_s, []).map(&:to_s) - [ "admin" ]
    errors.add(:capabilities, :invalid) unless (Array(capabilities) - allowed).empty?
  end

  def base_role_is_stable
    errors.add(:base_role, :invalid) if persisted? && base_role_changed? && memberships.exists?
  end
end
