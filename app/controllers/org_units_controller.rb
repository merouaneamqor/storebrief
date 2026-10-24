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

  def edit
    @org_unit = editable_store
  end

  def update
    @org_unit = editable_store
    if @org_unit.update(store_params)
      redirect_to org_units_path, notice: t("org_units.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # Tenant-scoped lookup; only store units carry a format and cluster.
  def editable_store
    tenant_scope.org_units.stores.find(params[:id])
  end

  def store_params
    params.require(:org_unit).permit(:store_format, :cluster_key)
  end
end
