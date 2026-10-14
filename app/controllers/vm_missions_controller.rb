class VmMissionsController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:morocco_ops) }
  before_action :set_mission, only: %i[show edit update destroy]
  before_action :load_stores, only: %i[new create edit update]

  def index
    @status = params[:status].presence_in(VmMission::STATUSES)
    @missions = tenant_scope.vm_missions.includes(:org_units, :created_by).deadline_first
    @missions = @missions.with_status(@status) if @status
  end

  def show
  end

  def new
    @mission = tenant_scope.vm_missions.new(deadline_on: Date.current + 7.days, status: "open")
  end

  def create
    @mission = tenant_scope.vm_missions.new(mission_attrs.merge(created_by: current_user))
    @mission.sync_targets!(params[:org_unit_ids])

    if @mission.save
      redirect_to vm_mission_path(@mission), notice: t("morocco.vm_missions.saved", title: @mission.title)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @mission.assign_attributes(mission_attrs)
    @mission.sync_targets!(params[:org_unit_ids])

    if @mission.save
      redirect_to vm_mission_path(@mission), notice: t("morocco.vm_missions.saved", title: @mission.title)
    else
      render :edit, status: :unprocessable_entity
    end
  end


  def destroy
    title = @mission.title
    @mission.destroy!
    redirect_to vm_missions_path, notice: t("morocco.vm_missions.deleted", title: title)
  end

  private

  def set_mission
    @mission = tenant_scope.vm_missions.find(params[:id])
  end

  def load_stores
    @stores = tenant_scope.org_units.stores.order(:name)
  end

  def mission_attrs
    params.require(:vm_mission).permit(
      :title_fr, :title_ar, :instructions_fr, :instructions_ar, :deadline_on, :status
    )
  end
end
