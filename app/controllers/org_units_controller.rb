class OrgUnitsController < ApplicationController
  before_action :require_hq

  def index
    @status = params[:status].presence_in(Vazivo::StoreStatus::BUCKETS) if tenant_scope.feature?(:morocco_ops)
    @region = tenant_scope.org_units.regions.find_by(id: params[:region_id]) if params[:region_id].present?
    if @status
      @status_stores = Vazivo::StoreStatus.for(tenant_scope).stores(@status)
    elsif @region
      @region_rows = Vazivo::TaskMonitoring.new(tenant_scope).store_rows_for(@region)
    else
      @roots = tenant_scope.org_units.roots.includes(children: :children).order(:name)
    end
  end
end
