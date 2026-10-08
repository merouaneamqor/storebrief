class VisitsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_visit_manager
  around_action :use_store_time_zone
  before_action :set_visit, only: %i[show edit update cancel]
  before_action :load_form_options, only: %i[new create edit update]

  def index
    @status = params[:status].presence_in(Visit::STATUSES)
    @visits = visit_scope.includes(:org_unit, :auditor).upcoming_first
    @visits = @visits.with_status(@status) if @status
  end

  def calendar
    @auditors = Visit.auditor_candidates(tenant_scope).where(id: visit_scope.select(:auditor_id))
    @units = calendar_units
    @unit = @units.find { |unit| unit.id.to_s == params[:unit_id].to_s }
    @auditor = @auditors.find_by(id: params[:auditor_id])

    visits = visit_scope.includes(:org_unit, :auditor)
    visits = visits.where(org_unit_id: @unit.descendant_stores.select(:id)) if @unit
    visits = visits.where(auditor_id: @auditor.id) if @auditor
    @calendar = Vazivo::VisitCalendar.new(visits: visits, view: params[:view], date: params[:date])
  end

  def show; end

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

  # Regions and areas that contain at least one store the user can see.
  def calendar_units
    visible_ids = store_scope.pluck(:id)
    tenant_scope.org_units.where(unit_type: %w[region area]).order(:name).select do |unit|
      unit.descendant_stores.where(id: visible_ids).exists?
    end
  end

  def load_form_options
    @stores = store_scope.order(:name)
    @auditors = Visit.auditor_candidates(tenant_scope)
    @audit_templates = tenant_scope.audit_templates.order(:title_fr)
  end

  def current_user_auditor
    current_user if @auditors.exists?(id: current_user.id)
  end

  def visit_attrs
    permitted = params.require(:visit).permit(:org_unit_id, :auditor_id, :planned_at, :notes, :audit_template_id)
    permitted[:org_unit_id] = nil if permitted.key?(:org_unit_id) && !@stores.exists?(id: permitted[:org_unit_id])
    permitted[:auditor_id] = nil if permitted.key?(:auditor_id) && !@auditors.exists?(id: permitted[:auditor_id])
    if permitted.key?(:audit_template_id) && !tenant_scope.audit_templates.exists?(id: permitted[:audit_template_id])
      permitted[:audit_template_id] = nil
    end
    permitted
  end
end
