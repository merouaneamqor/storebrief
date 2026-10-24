class CommunityPost < ApplicationRecord
  belongs_to :community
  belongs_to :user
  has_many :community_comments, dependent: :destroy

  validates :body, presence: true, length: { maximum: 2000 }
  validate :permitted_author

  private

  def permitted_author
    errors.add(:user, :invalid) unless community&.readable_by?(user)
  end
end
