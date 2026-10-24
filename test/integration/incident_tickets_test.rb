require "test_helper"

class IncidentTicketsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("ticket-flow", features: { morocco_ops: true })
    @category = TicketCategory.create!(tenant: @brand.tenant, name: "Repairs", department: "Maintenance", sla_hours: 12)
    sign_in @brand.store_user
  end

  test "store raises ticket and HQ assigns resolves and sees SLA dashboard" do
    assert_difference "TicketEvent.count", 1 do
      post incident_tickets_path, params: ticket_params
    end
    ticket = IncidentTicket.last
    assert_redirected_to ticket
    assert_equal "Maintenance", ticket.department
    patch incident_ticket_path(ticket), params: { status: "resolved" }
    assert_redirected_to app_root_path
    assert_equal "open", ticket.reload.status
    sign_in @brand.hq
    patch incident_ticket_path(ticket), params: { status: "in_progress", assignee_id: @brand.hq.id }
    assert_equal @brand.hq, ticket.reload.assignee
    ticket.update_columns(due_at: 1.hour.ago)
    get incident_tickets_path(breached: "1")
    assert_response :success
    assert_match ticket.title, response.body
    patch incident_ticket_path(ticket), params: { status: "resolved", assignee_id: @brand.hq.id }
    assert ticket.reload.resolved_at
    get incident_ticket_path(ticket)
    assert_select "h2", text: I18n.t("tickets.history", locale: :en)
  end

  test "role store tenant and feature boundaries are enforced" do
    post incident_tickets_path, params: ticket_params
    ticket = IncidentTicket.last
    other_store = @brand.tenant.org_units.create!(name: "Other", unit_type: "store", parent: @brand.region)
    outsider = create_user(@brand.tenant, org_unit: other_store, role: :store, email: "other@ticket.test")
    sign_in outsider
    get incident_ticket_path(ticket)
    assert_response :not_found
    assert_no_difference "IncidentTicket.count" do
      post incident_tickets_path, params: ticket_params
      assert_response :not_found
    end
    post ticket_categories_path, params: { ticket_category: { name: "Spoof", department: "IT", sla_hours: 2 } }
    assert_redirected_to app_root_path
    sign_in @brand.hq
    foreign = build_brand("tickets-other-tenant")
    params = ticket_params.deep_dup
    params[:incident_ticket][:ticket_category_id] = TicketCategory.create!(tenant: foreign.tenant, name: "Secret", department: "IT", sla_hours: 2).id
    post incident_tickets_path, params: params
    assert_response :not_found
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    get incident_tickets_path
    assert_redirected_to app_root_path
  end

  test "area sees descendant tickets only and forms render all locales" do
    area_unit = @brand.tenant.org_units.create!(name: "Area", unit_type: "area", parent: @brand.region)
    @brand.store.update!(parent: area_unit)
    area = create_user(@brand.tenant, org_unit: area_unit, role: :area)
    post incident_tickets_path, params: ticket_params
    ticket = IncidentTicket.last
    sign_in area
    get incident_ticket_path(ticket)
    assert_response :success
    other = @brand.tenant.org_units.create!(name: "Outside", unit_type: "store", parent: @brand.region)
    ticket.update!(org_unit: other)
    get incident_ticket_path(ticket)
    assert_response :not_found
    %w[fr ar es en].each do |locale|
      get new_incident_ticket_path(locale: locale)
      assert_response :success
      assert_match I18n.t("tickets.description", locale: locale), response.body
    end
  end

  test "audit failures and checklist items link to tickets and reject other store sources" do
    communication = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Audit", body_fr: "Check", format: "task", status: "draft")
    communication.send_to!([ @brand.store.id ])
    delivery = communication.deliveries.first
    delivery.update_columns(verdict: "non_conforme")
    get new_incident_ticket_path(source_type: "Delivery", source_id: delivery.id)
    assert_response :success
    post incident_tickets_path, params: ticket_params.merge(source_type: "Delivery", source_id: delivery.id)
    assert_equal delivery, IncidentTicket.last.source
    checklist = @brand.tenant.checklists.create!(author: @brand.hq, title_fr: "Checklist", status: "draft")
    item = checklist.checklist_items.create!(title_fr: "Inspect")
    checklist.send_to!([ @brand.store.id ])
    response = checklist.checklist_deliveries.first.checklist_item_responses.create!(checklist_item: item, completed: false)
    post incident_tickets_path, params: ticket_params.merge(source_type: "ChecklistItemResponse", source_id: response.id)
    assert_equal response, IncidentTicket.last.source
    delivery.update_columns(verdict: "conforme")
    post incident_tickets_path, params: ticket_params.merge(source_type: "Delivery", source_id: delivery.id)
    assert_response :not_found
  end

  test "custom management roles keep ticket visibility and assignment within granted scope" do
    post incident_tickets_path, params: ticket_params
    own = IncidentTicket.last
    other_store = @brand.tenant.org_units.create!(name: "Outside scope", unit_type: "store", parent: @brand.region)
    outside = IncidentTicket.create!(tenant: @brand.tenant, org_unit: other_store, author: @brand.hq, ticket_category: @category, title: "Outside incident", description: "Private")
    role = TenantRole.create!(tenant: @brand.tenant, name: "Scoped monitor", base_role: "hq", capabilities: %w[monitor])
    manager = create_user(@brand.tenant, org_unit: @brand.store, role: :hq, email: "scoped-manager@ticket.test")
    manager.memberships.first.update!(tenant_role: role)
    sign_in manager
    get incident_ticket_path(own)
    assert_response :success
    get incident_ticket_path(outside)
    assert_response :not_found
    outside.assignee = manager
    assert_not outside.valid?
    sign_in @brand.hq
    get incident_ticket_path(outside)
    assert_select "select[name=assignee_id] option[value='#{manager.id}']", count: 0
    patch incident_ticket_path(outside), params: { status: "in_progress", assignee_id: manager.id }
    assert_nil outside.reload.assignee_id
    assert_equal "open", outside.status
    role.update!(capabilities: [])
    sign_in manager
    get incident_ticket_path(own)
    assert_redirected_to app_root_path
    role.update!(capabilities: %w[monitor])
    wide_manager = create_user(@brand.tenant, org_unit: @brand.region, role: :hq, email: "wide-manager@ticket.test")
    wide_manager.memberships.first.update!(tenant_role: role)
    sign_in wide_manager
    get incident_tickets_path
    assert_response :success
    assert_select "form[action=?]", ticket_categories_path, count: 0
    assert_no_difference "TicketCategory.count" do
      post ticket_categories_path, params: { ticket_category: { name: "Forbidden", department: "IT", sla_hours: 1 } }
      assert_redirected_to app_root_path
    end
  end

  private

  def ticket_params
    { incident_ticket: { title: "Fridge broken", description: "Temperature rising", org_unit_id: @brand.store.id, ticket_category_id: @category.id, priority: "urgent" } }
  end
end
