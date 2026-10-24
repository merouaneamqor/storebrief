class ChecklistReviewsController < ApplicationController
  before_action -> { require_feature!(:checklists) }
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_hq_or_area(:monitor) }, only: %i[index show]
  before_action -> { require_hq_or_area(:verdicts, :escalate) }, only: :verdict

  def index
    @deliveries = scoped_deliveries(:monitor).includes(:org_unit, :validated_by, :checklist).order(updated_at: :desc).limit(100)
  end

  def show
    @delivery = scoped_deliveries(:monitor).find(params[:id])
    @responses = @delivery.checklist_item_responses.includes(photo_attachment: :blob).index_by(&:checklist_item_id)
  end

  def verdict
    delivery = scoped_deliveries(:verdicts, :escalate).find(params[:id])
    delivery.apply_review_verdict!(params[:verdict], note: params[:verdict_note], by: current_user)
    redirect_to checklist_review_path(delivery), notice: t("morocco.verdict.saved"), status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to checklist_review_path(delivery), alert: error.message, status: :see_other
  end

  def comment
    capability = store_user? ? :execute : :monitor
    delivery = scoped_deliveries(capability).find(params[:id])
    attributes = params.require(:checklist_delivery_comment).permit(:body, :parent_id, mentioned_user_ids: [])
    comment = delivery.checklist_delivery_comments.new(attributes.merge(tenant: tenant_scope, user: current_user))
    flash[comment.save ? :notice : :alert] = comment.persisted? ? t("morocco.comments.posted") : t("morocco.comments.invalid")
    destination = store_user? ? checklists_delivery_path(delivery) : checklist_review_path(delivery)
    redirect_to "#{destination}#comments", status: :see_other
  end

  private

  def scoped_deliveries(*capabilities)
    ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: tenant_scope.id, status: "sent" },
      org_unit_id: current_user.permitted_store_ids(*capabilities))
  end
end
