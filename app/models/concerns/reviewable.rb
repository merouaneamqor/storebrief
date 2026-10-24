# HQ approval state shared by Communication and PlaybookDeployRequest.
# review_status is nil when no review was ever requested.
module Reviewable
  extend ActiveSupport::Concern

  REVIEW_STATUSES = %w[pending_review approved rejected].freeze
  REVIEW_COLUMNS = %w[review_status reviewed_by_id reviewed_at review_note].freeze

  included do
    belongs_to :reviewed_by, class_name: "User", optional: true
    has_many :approval_events, as: :subject, dependent: :destroy

    validates :review_status, inclusion: { in: REVIEW_STATUSES }, allow_nil: true

    scope :pending_review, -> { where(review_status: "pending_review") }
  end

  def review_pending?
    review_status == "pending_review"
  end

  def review_approved?
    review_status == "approved"
  end

  def review_rejected?
    review_status == "rejected"
  end
end
