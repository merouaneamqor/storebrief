class DashboardController < ApplicationController
  def show
    if hq_user?
      load_hq_today
    elsif tenant_scope.feature?(:morocco_ops)
      @radar = Vazivo::Radar.for(user: current_user, tenant: tenant_scope)
    else
      load_store_fallback
    end
  end

  private

  def load_hq_today
    if tenant_scope.feature?(:morocco_ops)
      @board = Vazivo::HqBoard.for(tenant_scope)
    else
      @communications = tenant_scope.communications.includes(:author).order(created_at: :desc).limit(8)
      @checklists = tenant_scope.checklists.includes(:author).order(created_at: :desc).limit(5)
      @store_count = tenant_scope.org_units.stores.count
      @region_count = tenant_scope.org_units.regions.count
      @sent_count = tenant_scope.communications.sent.count
    end
  end

  def load_store_fallback
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
