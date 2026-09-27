class InboxController < ApplicationController
  before_action :set_store

  def index
    @deliveries = Delivery.joins(:communication)
                          .where(org_unit: @store, communications: { tenant_id: tenant_scope.id, status: "sent" })
                          .includes(:communication)
                          .order("communications.created_at DESC")
  end

  def show
    @delivery = Delivery.joins(:communication)
                        .where(org_unit: @store, communications: { tenant_id: tenant_scope.id })
                        .includes(:communication)
                        .find(params[:id])
    @communication = @delivery.communication
  end

  def complete
    @delivery = Delivery.joins(:communication)
                        .where(org_unit: @store, communications: { tenant_id: tenant_scope.id })
                        .includes(:communication)
                        .find(params[:id])

    if @delivery.communication.task?
      @delivery.complete!
      redirect_to inbox_path(@delivery), notice: t("inbox.task_done")
    else
      @delivery.mark_read!
      redirect_to inbox_path(@delivery), notice: t("inbox.marked_read")
    end
  end

  private

  def set_store
    @store = current_user.store_org_unit
    return if @store

    redirect_to root_path, alert: t("errors.no_store")
  end
end
