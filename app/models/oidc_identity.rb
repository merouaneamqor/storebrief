class OidcIdentity < ApplicationRecord
  belongs_to :tenant
  belongs_to :user
  has_many :memberships, dependent: :destroy

  validates :issuer, :subject, presence: true, length: { maximum: 255 }
  validates :subject, uniqueness: { scope: %i[tenant_id issuer] }
  validates :user_id, uniqueness: true
  validate :same_tenant

  private

  def same_tenant
    errors.add(:user, :invalid) unless user && user.tenant_id == tenant_id && !user.super_admin?
  end
end
