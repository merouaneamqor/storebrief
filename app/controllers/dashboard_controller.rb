class DashboardController < ApplicationController
  def show
    if hq_user?
      @communications = tenant_scope.communications.includes(:author).order(created_at: :desc).limit(8)
      @checklists = tenant_scope.checklists.includes(:author).order(created_at: :desc).limit(5)
      @store_count = tenant_scope.org_units.stores.count
      @region_count = tenant_scope.org_units.regions.count
      @sent_count = tenant_scope.communications.sent.count
    else
      store = current_user.store_org_unit
      @deliveries = if store
                      Delivery.joins(:communication)
                              .where(org_unit: store, communications: { tenant_id: tenant_scope.id, status: "sent" })
                              .includes(:communication)
                              .order("communications.created_at DESC")
                              .limit(8)
      else
                      Delivery.none
      end
      @checklist_deliveries = if store
                                ChecklistDelivery.joins(:checklist)
                                                 .where(org_unit: store, checklists: { tenant_id: tenant_scope.id, status: "sent" })
                                                 .includes(:checklist)
                                                 .order("checklists.created_at DESC")
                                                 .limit(5)
      else
                                ChecklistDelivery.none
      end
    end
  end
end
