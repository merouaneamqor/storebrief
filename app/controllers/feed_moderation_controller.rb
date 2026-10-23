class FeedModerationController < FeedEngagementController
  before_action :require_hq

  def index
    @posts = FeedPost.where(tenant: tenant_scope).where.not(status: "removed").includes(:user, :org_unit).order(created_at: :desc).limit(100)
    @comments = FeedComment.where(tenant: tenant_scope).visible.includes(:user, subject: :org_unit).order(created_at: :desc).limit(100)
  end
end
