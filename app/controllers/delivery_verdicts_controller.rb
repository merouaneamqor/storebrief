class DeliveryVerdictsController < ApplicationController
  before_action -> { require_hq_or_area(:verdicts, :escalate) }
  before_action -> { require_feature!(:morocco_ops) }

  def create
    delivery = Delivery.joins(:communication)
                       .where(communications: { tenant_id: tenant_scope.id })
                       .find(params[:delivery_id])
    assert_area_can_verdict!(delivery)
    awaiting = delivery.pending_approval?
    delivery.apply_verdict!(params[:verdict], note: params[:verdict_note], by: current_user)
    notice = if awaiting
      params[:verdict].to_s == Delivery::APPROVAL_REJECT_VERDICT ? t("morocco.approval.rejected") : t("morocco.approval.approved")
    else
      t("morocco.verdict.saved")
    end
    redirect_to delivery.communication, notice: notice
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ArgumentError) ? e.message : e.record.errors.full_messages.to_sentence
    redirect_back fallback_location: app_root_path, alert: message
  end

  private

  def assert_area_can_verdict!(delivery)
    return if hq_user?

    allowed = current_user.permitted_store_ids(:verdicts, :escalate).include?(delivery.org_unit_id)
    raise ArgumentError, t("auth.hq_required") unless allowed
  end
end
