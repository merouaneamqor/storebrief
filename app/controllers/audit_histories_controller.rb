class AuditHistoriesController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_hq_or_area(:visits) }

  def show
    @regions = visible_regions
    @stores = store_scope.order(:name)
    @region = @regions.find { |unit| unit.id.to_s == params[:region_id].to_s }
    @store = @stores.find_by(id: params[:store_id]) if params[:store_id].present?

    @history = Vazivo::AuditHistory.for(
      tenant_scope,
      store_ids: visible_store_ids,
      store: @store,
      region: @region
    )

    respond_to do |format|
      format.html
      format.csv do
        filename = "audit-history-#{tenant_scope.slug}-#{Time.zone.today}.csv"
        send_data Vazivo::AuditHistory.csv(@history), filename: filename, type: "text/csv"
      end
    end
  end

  private

  def store_scope
    if hq_user?
      tenant_scope.org_units.stores
    elsif area_user?
      tenant_scope.org_units.stores.where(id: current_user.permitted_store_ids(:visits))
    else
      OrgUnit.none
    end
  end

  def visible_store_ids
    if @store
      [ @store.id ]
    elsif @region
      @region.descendant_stores.where(id: store_scope.select(:id)).pluck(:id)
    else
      store_scope.pluck(:id)
    end
  end

  def visible_regions
    visible_ids = store_scope.pluck(:id)
    return [] if visible_ids.empty?

    tenant_scope.org_units.regions.order(:name).select do |unit|
      unit.descendant_stores.where(id: visible_ids).exists?
    end
  end
end
