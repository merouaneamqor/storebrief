class FeedReaction < ApplicationRecord
  include FeedEntry
  KINDS = %w[helpful thanks acknowledged].freeze
  validates :kind, inclusion: { in: KINDS }
  validates :user_id, uniqueness: { scope: [ :subject_type, :subject_id ] }
end
