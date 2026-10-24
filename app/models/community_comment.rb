class CommunityComment < ApplicationRecord
  belongs_to :community_post
  belongs_to :user

  validates :body, presence: true, length: { maximum: 1000 }
  validate :permitted_author

  private

  def permitted_author
    errors.add(:user, :invalid) unless community_post&.community&.readable_by?(user)
  end
end
