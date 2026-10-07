class VisitsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_visit_manager
  around_action :use_store_time_zone
  before_action :set_visit, only: %i[edit update cancel]
  before_action :load_form_options, only: %i[new create edit update]

  def index
    @status = params[:status].presence_in(Visit::STATUSES)
    @visits = visit_scope.includes(:org_unit, :auditor).upcoming_first
    @visits = @visits.with_status(@status) if @status
  end

  def new
    @visit = tenant_scope.visits.new(planned_at: Time.zone.now.change(hour: 10, min: 0) + 1.day, auditor: current_user_auditor)
  end

  def create
    @visit = tenant_scope.visits.new(visit_attrs.merge(created_by: current_user))

    if @visit.save
      redirect_to visits_path, notice: t("morocco.visits.saved", store: @visit.org_unit.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    return if @visit.editable?

    redirect_to visits_path, alert: t("morocco.visits.not_editable")
  end

  def update
    unless @visit.editable?
      redirect_to visits_path, alert: t("morocco.visits.not_editable")
      return
    end

    if @visit.update(visit_attrs)
      redirect_to visits_path, notice: t("morocco.visits.saved", store: @visit.org_unit.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def cancel
    @visit.cancel!(reason: params[:cancel_reason].to_s.strip)
    redirect_to visits_path, notice: t("morocco.visits.cancelled", store: @visit.org_unit.name)
  rescue ArgumentError => e
    redirect_to visits_path, alert: e.message
  end

  private

  def require_visit_manager
    return if hq_user? || current_user.area?

    redirect_to app_root_path, alert: t("morocco.visits.access_required")
  end

  def use_store_time_zone(&)
    Time.use_zone(Vazivo::Schedule::ZONE, &)
  end

  def set_visit
    @visit = visit_scope.find(params[:id])
  end

  def visit_scope
    scope = tenant_scope.visits
    hq_user? ? scope : scope.where(org_unit_id: store_scope.select(:id))
  end

  # HQ plans for every store; area users only for stores under their area.
  def store_scope
    stores = tenant_scope.org_units.stores
    return stores if hq_user?

    store_ids = current_user.memberships.where(role: "area").includes(:org_unit)
                            .flat_map { |m| m.org_unit.descendant_stores.pluck(:id) }
    stores.where(id: store_ids)
  end

  def load_form_options
    @stores = store_scope.order(:name)
    @auditors = Visit.auditor_candidates(tenant_scope)
  end

  def current_user_auditor
    current_user if @auditors.exists?(id: current_user.id)
  end

  def visit_attrs
    permitted = params.require(:visit).permit(:org_unit_id, :auditor_id, :planned_at, :notes)
    permitted[:org_unit_id] = nil if permitted.key?(:org_unit_id) && !@stores.exists?(id: permitted[:org_unit_id])
    permitted[:auditor_id] = nil if permitted.key?(:auditor_id) && !@auditors.exists?(id: permitted[:auditor_id])
    permitted
  end
end
