class DeliveryVerdictsController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:morocco_ops) }

  def create
    delivery = Delivery.joins(:communication)
                       .where(communications: { tenant_id: tenant_scope.id })
                       .find(params[:delivery_id])
    delivery.apply_verdict!(params[:verdict], note: params[:verdict_note], by: current_user)
    redirect_to delivery.communication, notice: t("morocco.verdict.saved")
  rescue ArgumentError => e
    redirect_back fallback_location: app_root_path, alert: e.message
  end
end
