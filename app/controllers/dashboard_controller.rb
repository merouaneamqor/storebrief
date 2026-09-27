class DashboardController < ApplicationController
  def show
    if hq_user?
      @communications = tenant_scope.communications.includes(:author).order(created_at: :desc).limit(10)
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
                              .limit(10)
                    else
                      Delivery.none
                    end
    end
  end
end
