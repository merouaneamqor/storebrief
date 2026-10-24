require "test_helper"

class IncidentTicketTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("ticket-model")
    @category = TicketCategory.create!(tenant: @brand.tenant, name: "Cooling", department: "Maintenance", sla_hours: 24)
  end

  test "snapshots category SLA and records immutable workflow events" do
    ticket = build_ticket
    freeze_time do
      ticket.save!
      assert_equal 24.hours.from_now, ticket.due_at
      @category.update!(sla_hours: 2)
      assert_equal 24.hours.from_now, ticket.reload.due_at
      assert_not ticket.breached?
      travel 25.hours
      assert ticket.breached?
      assert_includes IncidentTicket.breached, ticket
      ticket.workflow!(actor: @brand.hq, status: "in_progress", assignee: @brand.hq)
      ticket.workflow!(actor: @brand.hq, status: "resolved", assignee: @brand.hq)
      assert ticket.breached?
      assert_equal 4, ticket.ticket_events.count
      assert_raises(ActiveRecord::ReadOnlyRecord) { ticket.ticket_events.first.update!(kind: "status") }
      assert_raises(ActiveRecord::RecordInvalid) { ticket.workflow!(actor: @brand.hq, status: "in_progress", assignee: @brand.hq) }
    end
  end

  test "resolved on time remains within SLA and tenant boundaries reject spoofing" do
    ticket = build_ticket
    ticket.save!
    ticket.workflow!(actor: @brand.hq, status: "resolved", assignee: @brand.hq)
    travel 30.hours do
      assert_not ticket.breached?
      assert_not_includes IncidentTicket.breached, ticket
    end
    foreign = build_brand("ticket-foreign")
    ticket.assignee = foreign.hq
    assert_not ticket.valid?
    ticket.assignee = @brand.store_user
    assert_not ticket.valid?
    ticket.assignee = nil
    ticket.org_unit = foreign.store
    assert_not ticket.valid?
    @category.sla_hours = 0
    assert_not @category.valid?
  end

  private

  def build_ticket
    IncidentTicket.new(tenant: @brand.tenant, org_unit: @brand.store, author: @brand.store_user, ticket_category: @category, title: "Broken fridge", description: "Cooling stopped")
  end
end
