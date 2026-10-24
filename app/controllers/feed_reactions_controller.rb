class FeedReactionsController < FeedEngagementController
  def create
    subject = feed_subject
    reaction = FeedReaction.find_or_initialize_by(tenant: tenant_scope, user: current_user, subject: subject)
    reaction.kind = params[:kind]
    save_entry(reaction)
  end

  def destroy
    FeedReaction.where(tenant: tenant_scope, user: current_user).find(params[:id]).destroy!
    feed_redirect
  end
end
