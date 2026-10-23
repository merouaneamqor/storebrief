class FeedCommentsController < FeedEngagementController
  def create
    comment = FeedComment.new(tenant: tenant_scope, user: current_user, subject: feed_subject, body: params[:body])
    if comment.save
      Vazivo::FeedNotifications.comment!(comment)
    else
      flash[:alert] = comment.errors.full_messages.to_sentence
    end
    feed_redirect
  end

  def destroy
    require_hq
    return if performed?

    FeedComment.where(tenant: tenant_scope).find(params[:id]).update_columns(removed_at: Time.current)
    feed_redirect
  end
end
