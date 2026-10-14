class DeliveryVerdictsController < ApplicationController
  before_action -> { require_hq_or_area(:verdicts, :escalate) }
  before_action -> { require_feature!(:morocco_ops) }

  def create
    delivery = Delivery.joins(:communication)
                       .where(communications: { tenant_id: tenant_scope.id })
                       .find(params[:delivery_id])
    assert_area_can_verdict!(delivery)
    delivery.apply_verdict!(params[:verdict], note: params[:verdict_note], by: current_user)
    redirect_to delivery.communication, notice: t("morocco.verdict.saved")
  rescue ArgumentError => e
    redirect_back fallback_location: app_root_path, alert: e.message
  end

  private

  def assert_area_can_verdict!(delivery)
    return if hq_user?

    allowed = current_user.area_org_unit&.descendant_stores&.exists?(id: delivery.org_unit_id)
    raise ArgumentError, t("auth.hq_required") unless allowed
  end
end
