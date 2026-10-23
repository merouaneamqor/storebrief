class FeedEngagementController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_feed_role

  private

  def require_feed_role
    redirect_to app_root_path, alert: t("auth.hq_required") unless hq_user? || store_user?
  end

  def feed_subject
    scope = case params[:subject_type]
    when "Delivery"
      Delivery.joins(:communication).where(communications: { tenant_id: tenant_scope.id, status: "sent", format: Vazivo::Newsfeed::FORMATS })
    when "FeedPost"
      FeedPost.where(tenant: tenant_scope, status: "published")
    else
      raise ActiveRecord::RecordNotFound
    end
    scope = scope.where(org_unit_id: current_user.store_org_unit&.id) unless hq_user?
    scope.find(params[:subject_id])
  end

  def feed_redirect
    redirect_to(hq_user? ? feed_moderation_path : newsfeeds_path, status: :see_other)
  end

  def save_entry(entry)
    flash[:alert] = entry.errors.full_messages.to_sentence unless entry.save
    feed_redirect
  end
end
