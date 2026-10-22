class BroadcastAcknowledgementsController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action -> { require_feature!(:morocco_ops) }

  def create
    raise ActiveRecord::RecordNotFound unless store_user? && current_user.store_org_unit

    delivery = Delivery.joins(:communication)
                       .where(org_unit_id: current_user.store_org_unit.id, communications: { tenant_id: tenant_scope.id, status: "sent" })
                       .find(params[:delivery_id])
    delivery.acknowledge!(by: current_user)
    redirect_to inbox_path(delivery), notice: t("broadcasts.acknowledged")
  rescue ArgumentError => e
    redirect_to inbox_path(delivery), alert: e.message
  end
end
