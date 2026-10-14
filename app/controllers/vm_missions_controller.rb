class VmMissionsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_hq, except: %i[index show]
  before_action :require_mission_viewer!, only: %i[index show]
  before_action :set_mission, only: %i[show edit update destroy]
  before_action :load_stores, only: %i[new create edit update]

  def index
    @status = params[:status].presence_in(VmMission::STATUSES)
    @missions = mission_scope.includes(:org_units, :created_by).deadline_first
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
    apply_attachment_uploads!(@mission)

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
    purge_removed_attachments!(@mission)
    apply_attachment_uploads!(@mission)

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
    @mission = mission_scope.includes(attachments_attachments: :blob).find(params[:id])
  end

  def load_stores
    @stores = tenant_scope.org_units.stores.order(:name)
  end

  def mission_attrs
    params.require(:vm_mission).permit(
      :title_fr, :title_ar, :instructions_fr, :instructions_ar,
      :deadline_on, :status, :version_label
    )
  end

  def apply_attachment_uploads!(mission)
    files = Array(params.dig(:vm_mission, :attachments)).compact_blank
    mission.attachments.attach(files) if files.any?
  end

  def purge_removed_attachments!(mission)
    ids = Array(params.dig(:vm_mission, :remove_attachment_ids)).map(&:to_i).reject(&:zero?)
    return if ids.empty?

    mission.attachments.attachments.where(id: ids).find_each(&:purge)
  end

  def require_mission_viewer!
    return if hq_user?
    return if store_user? && current_user.store_org_unit.present?

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def mission_scope
    scope = tenant_scope.vm_missions
    return scope if hq_user?

    store = current_user.store_org_unit
    scope.for_store(store)
  end
end
