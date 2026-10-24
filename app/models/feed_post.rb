class FeedPost < ApplicationRecord
  belongs_to :tenant
  belongs_to :org_unit
  belongs_to :user
  has_many :feed_comments, as: :subject, dependent: :destroy
  has_many :feed_reactions, as: :subject, dependent: :destroy

  validates :body, presence: true, length: { maximum: 2000 }
  validates :status, inclusion: { in: %w[pending published removed] }
  validate :store_author

  private

  def store_author
    return if user && org_unit && tenant_id == user.tenant_id && tenant_id == org_unit.tenant_id &&
      org_unit.unit_type == "store" && user.memberships.exists?(org_unit: org_unit, role: "store") &&
      !user.hq? && !user.area?

    errors.add(:base, :invalid)
  end
end
