class StoresController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }

  def show
    @store = visible_stores.find(params[:id])
    @radar = Vazivo::Radar.for_store(user: current_user, tenant: tenant_scope, store: @store)
    render "dashboard/show"
  end

  private

  def visible_stores
    if hq_user?
      tenant_scope.org_units.stores
    elsif (area = current_user.area_org_unit)
      area.descendant_stores.where(tenant_id: tenant_scope.id)
    elsif (store = current_user.store_org_unit)
      tenant_scope.org_units.stores.where(id: store.id)
    else
      OrgUnit.none
    end
  end
end
