class VmMissionsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_hq, except: %i[index show submit_proof review]
  before_action :require_mission_viewer!, only: %i[index show]
  before_action :require_store_submitter!, only: :submit_proof
  before_action :require_hq_or_area_reviewer!, only: :review
  before_action :set_mission, only: %i[show edit update destroy submit_proof]
  before_action :set_mission_for_review, only: :review
  before_action :load_stores, only: %i[new create edit update]

  def index
    @status = params[:status].presence_in(VmMission::STATUSES)
    @missions = mission_scope.includes(:org_units, :created_by).deadline_first
    @missions = @missions.with_status(@status) if @status
  end

  def show
    @targets = @mission.vm_mission_targets.includes(
      :org_unit,
      :validated_by,
      photo_before_attachment: :blob,
      photo_after_attachment: :blob
    )
    if store_user?
      @store_target = @targets.find { |target| target.org_unit_id == current_user.store_org_unit&.id }
    elsif area_user?
      store_ids = current_user.area_org_unit&.descendant_stores&.pluck(:id) || []
      @targets = @targets.select { |target| store_ids.include?(target.org_unit_id) }
    end
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

  def submit_proof
    target = @mission.vm_mission_targets.find_by!(org_unit_id: current_user.store_org_unit.id)
    target.attach_photos!(before: params[:photo_before], after: params[:photo_after])
    target.submit_for_review!
    redirect_to vm_mission_path(@mission), notice: t("morocco.vm_missions.proof.submitted")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ArgumentError) ? e.message : e.record.errors.full_messages.to_sentence
    redirect_to vm_mission_path(@mission), alert: message
  end

  def review
    target = @mission.vm_mission_targets.find(params[:target_id])
    assert_area_can_review!(target)
    target.apply_verdict!(params[:verdict], note: params[:verdict_note], by: current_user)
    notice = if params[:verdict].to_s == VmMissionTarget::REJECT_VERDICT
      t("morocco.vm_missions.proof.rejected")
    else
      t("morocco.vm_missions.proof.approved")
    end
    redirect_to vm_mission_path(@mission), notice: notice
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ArgumentError) ? e.message : e.record.errors.full_messages.to_sentence
    redirect_to vm_mission_path(@mission), alert: message
  end

  private

  def set_mission
    @mission = mission_scope.includes(attachments_attachments: :blob).find(params[:id])
  end

  def set_mission_for_review
    @mission = tenant_scope.vm_missions.includes(attachments_attachments: :blob).find(params[:id])
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
    return if area_user? && user_allows?(:verdicts)
    return if store_user? && current_user.store_org_unit.present?

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def require_store_submitter!
    return if store_user? && current_user.store_org_unit.present?

    redirect_to app_root_path, alert: t("auth.hq_required")
  end

  def require_hq_or_area_reviewer!
    require_hq_or_area(:verdicts)
  end

  def assert_area_can_review!(target)
    return if hq_user?

    allowed = current_user.area_org_unit&.descendant_stores&.exists?(id: target.org_unit_id)
    raise ArgumentError, t("auth.hq_required") unless allowed
  end

  def mission_scope
    scope = tenant_scope.vm_missions
    return scope if hq_user?
    return scope if area_user? && user_allows?(:verdicts)

    store = current_user.store_org_unit
    scope.for_store(store)
  end
end
