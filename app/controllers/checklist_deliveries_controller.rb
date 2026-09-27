class ChecklistDeliveriesController < ApplicationController
  before_action :set_store
  before_action :set_delivery, only: %i[show submit_item complete]

  def index
    @deliveries = ChecklistDelivery.joins(:checklist)
                                   .where(org_unit: @store, checklists: { tenant_id: tenant_scope.id, status: "sent" })
                                   .includes(:checklist)
                                   .order("checklists.created_at DESC")
  end

  def show
    @checklist = @delivery.checklist
    @items = @checklist.checklist_items
    @responses = @delivery.checklist_item_responses.includes(photo_attachment: :blob).index_by(&:checklist_item_id)
  end

  def submit_item
    item = @delivery.checklist.checklist_items.find(params[:item_id])
    response = @delivery.checklist_item_responses.find_or_initialize_by(checklist_item: item)
    response.completed = true
    response.notes = params[:notes]
    response.client_uuid = params[:client_uuid] if params[:client_uuid].present?
    response.photo.attach(params[:photo]) if params[:photo].present?
    response.save!
    @delivery.complete_if_ready!

    redirect_to checklists_delivery_path(@delivery), notice: t("checklists.mark_done")
  end

  def complete
    @delivery.checklist.checklist_items.each do |item|
      @delivery.checklist_item_responses.find_or_create_by!(checklist_item: item) do |r|
        r.completed = true
      end
    end
    @delivery.update!(status: "completed", completed_at: Time.current)
    redirect_to checklists_delivery_path(@delivery), notice: t("checklists.completed")
  end

  private

  def set_store
    @store = current_user.store_org_unit
    return if @store

    redirect_to app_root_path, alert: t("errors.no_store")
  end

  def set_delivery
    @delivery = ChecklistDelivery.joins(:checklist)
                                 .where(org_unit: @store, checklists: { tenant_id: tenant_scope.id })
                                 .find(params[:id])
  end
end
