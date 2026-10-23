class DeliveryCommentsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :set_delivery

  def create
    comment = @delivery.delivery_comments.new(
      user: current_user,
      body: comment_params[:body],
      parent_id: comment_params[:parent_id].presence,
      mentioned_user_ids: Array(comment_params[:mentioned_user_ids]).reject(&:blank?)
    )

    if comment.save
      redirect_to after_create_path, notice: t("morocco.comments.posted")
    else
      redirect_to after_create_path, alert: comment.errors.full_messages.to_sentence.presence || t("morocco.comments.invalid")
    end
  end

  private

  def set_delivery
    @delivery = Delivery.joins(:communication)
                        .where(communications: { tenant_id: tenant_scope.id })
                        .find(params[:delivery_id])
    assert_can_comment!(@delivery)
  end

  def assert_can_comment!(delivery)
    return if hq_user?
    return if store_user? && current_user.store_org_unit&.id == delivery.org_unit_id
    return if area_user? && user_allows?(:monitor, org_unit: delivery.org_unit)

    raise ActiveRecord::RecordNotFound
  end

  def comment_params
    params.require(:delivery_comment).permit(:body, :parent_id, mentioned_user_ids: [])
  end

  def after_create_path
    if store_user?
      inbox_path(@delivery, anchor: "comments")
    else
      communication_path(@delivery.communication, anchor: "delivery-comment-#{@delivery.id}")
    end
  end
end
