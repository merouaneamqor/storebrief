class FeedComment < ApplicationRecord
  include FeedEntry
  validates :body, presence: true, length: { maximum: 2000 }
  scope :visible, -> { where(removed_at: nil) }
end
