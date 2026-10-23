class TenantRolesController < ApplicationController
  before_action :authenticate_hq_admin!
  before_action -> { require_feature!(:morocco_ops) }
  before_action :set_role, only: %i[update destroy]

  def index
    load_matrix
    @role = tenant_scope.tenant_roles.new(base_role: "area")
  end

  def create
    @role = tenant_scope.tenant_roles.new(role_params)
    if @role.save
      redirect_to tenant_roles_path, notice: t("tenant_roles.saved")
    else
      load_matrix
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @role.update(role_params)
      redirect_to tenant_roles_path, notice: t("tenant_roles.saved")
    else
      load_matrix
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    if @role.destroy
      redirect_to tenant_roles_path, notice: t("tenant_roles.deleted")
    else
      redirect_to tenant_roles_path, alert: t("tenant_roles.in_use")
    end
  end

  def assign
    role = tenant_scope.tenant_roles.find(params[:tenant_role_id]) if params[:tenant_role_id].present?
    membership = if params[:membership_id].present?
      Membership.joins(:user, :org_unit)
        .where(users: { tenant_id: tenant_scope.id, super_admin: false }, org_units: { tenant_id: tenant_scope.id })
        .find(params[:membership_id])
    else
      raise ActiveRecord::RecordNotFound unless role

      user = tenant_scope.users.where(super_admin: false).find(params[:user_id])
      unit = tenant_scope.org_units.find(params[:org_unit_id])
      user.memberships.new(org_unit: unit, role: role.base_role)
    end
    # The permission matrix cannot remove or convert a built-in tenant admin.
    if membership.persisted? && membership.role == "hq" && membership.tenant_role_id.nil?
      redirect_to tenant_roles_path, alert: t("tenant_roles.protected_admin")
      return
    end
    if membership.update(tenant_role: role)
      redirect_to tenant_roles_path, notice: t("tenant_roles.saved")
    else
      redirect_to tenant_roles_path, alert: t("tenant_roles.invalid_assignment")
    end
  end

  private

  def set_role
    @role = tenant_scope.tenant_roles.find(params[:id])
  end

  def load_matrix
    @roles = tenant_scope.tenant_roles.order(:name)
    @memberships = Membership.joins(:user, :org_unit)
      .where(users: { tenant_id: tenant_scope.id, super_admin: false }, org_units: { tenant_id: tenant_scope.id })
      .includes(:user, :org_unit, :tenant_role).order(:id)
  end

  def role_params
    params.require(:tenant_role).permit(:name, :base_role, capabilities: [])
  end
end
