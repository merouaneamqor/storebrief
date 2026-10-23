class IncidentTicketsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_ticket_role

  def index
    @tickets = ticket_scope.includes(:org_unit, :ticket_category, :assignee).order(created_at: :desc)
    @breached_count = @tickets.breached.count
    @open_count = @tickets.unresolved.count
    @tickets = @tickets.breached if params[:breached] == "1"
    @tickets = @tickets.limit(100)
    @categories = TicketCategory.where(tenant: tenant_scope).order(:name)
  end

  def new
    @ticket = IncidentTicket.new
    if params[:source_id].present?
      source = ticket_source
      @ticket.source = source
      @ticket.org_unit_id = source.is_a?(Delivery) ? source.org_unit_id : source.checklist_delivery.org_unit_id
    end
    prepare_form
  end

  def create
    @ticket = IncidentTicket.new(ticket_params.merge(tenant: tenant_scope, author: current_user))
    @ticket.org_unit = stores.find(params.dig(:incident_ticket, :org_unit_id))
    @ticket.ticket_category = TicketCategory.where(tenant: tenant_scope).find(params.dig(:incident_ticket, :ticket_category_id))
    @ticket.source = ticket_source if params[:source_id].present?
    if @ticket.save
      redirect_to @ticket, notice: t("tickets.saved")
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @ticket = ticket_scope.find(params[:id])
    @events = @ticket.ticket_events.includes(:actor).order(:created_at, :id)
    @assignees = tenant_scope.users.select { |user| user.allows?(:monitor, org_unit: @ticket.org_unit) }
  end

  def update
    require_hq_or_area(:monitor)
    return if performed?

    ticket = ticket_scope.find(params[:id])
    assignee = tenant_scope.users.find(params[:assignee_id]) if params[:assignee_id].present?
    ticket.workflow!(actor: current_user, status: params[:status].to_s, assignee: assignee)
    redirect_to ticket, notice: t("tickets.saved"), status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to ticket, alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end

  private

  def ticket_params
    params.require(:incident_ticket).permit(:title, :description, :priority)
  end

  def require_ticket_role
    redirect_to app_root_path, alert: t("auth.hq_required") unless hq_user? || area_user? || store_user?
  end

  def stores
    scope = tenant_scope.org_units.stores
    return scope if super_admin?

    capability = store_user? ? :execute : :monitor
    scope.where(id: current_user.permitted_store_ids(capability))
  end

  def ticket_scope
    IncidentTicket.where(tenant: tenant_scope, org_unit_id: stores.select(:id))
  end

  def ticket_source
    case params[:source_type]
    when "Delivery"
      Delivery.joins(:communication).where(communications: { tenant_id: tenant_scope.id }, org_unit_id: stores.select(:id), verdict: "non_conforme").find(params[:source_id])
    when "ChecklistItemResponse"
      ChecklistItemResponse.joins(checklist_delivery: :checklist).where(checklists: { tenant_id: tenant_scope.id }, checklist_deliveries: { org_unit_id: stores.select(:id) }).find(params[:source_id])
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def prepare_form
    @stores = stores.order(:name)
    @categories = TicketCategory.where(tenant: tenant_scope).order(:name)
  end
end
