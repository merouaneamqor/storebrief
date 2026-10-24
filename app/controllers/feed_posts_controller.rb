class FeedPostsController < FeedEngagementController
  def create
    unless store_user?
      redirect_to app_root_path, alert: t("auth.hq_required")
      return
    end
    save_entry(FeedPost.new(tenant: tenant_scope, user: current_user,
                           org_unit: current_user.store_org_unit, body: params[:body]))
  end

  def publish
    require_hq
    return if performed?

    post = FeedPost.where(tenant: tenant_scope, status: "pending").find(params[:id])
    post.update!(status: "published")
    Vazivo::FeedNotifications.published!(post)
    feed_redirect
  end

  def destroy
    require_hq
    return if performed?

    FeedPost.where(tenant: tenant_scope).find(params[:id]).update!(status: "removed")
    feed_redirect
  end
end
