class OrgUnitsController < ApplicationController
  before_action :require_hq

  def index
    @status = params[:status].presence_in(Vazivo::StoreStatus::BUCKETS) if tenant_scope.feature?(:morocco_ops)
    if @status
      @status_stores = Vazivo::StoreStatus.for(tenant_scope).stores(@status)
    else
      @roots = tenant_scope.org_units.roots.includes(children: :children).order(:name)
    end
  end
end
