class TenantsController < ApplicationController
  before_action :require_super_admin

  def index
    @tenants = Tenant.order(:name)
    @store_counts = OrgUnit.stores.group(:tenant_id).count
    @user_counts = User.where(super_admin: false).group(:tenant_id).count
    @brief_counts = Communication.sent.group(:tenant_id).count
  end

  def switch
    tenant = Tenant.find(params[:tenant_id])
    session[:acting_tenant_id] = tenant.id
    Current.tenant = tenant

    notice = t("tenants.switched", tenant: tenant.name)
    if params[:to] == "dashboard"
      redirect_to app_root_path, notice: notice
    else
      redirect_back fallback_location: app_root_path, notice: notice
    end
  end
end
