require "test_helper"

class VazivoExceptionDrilldownTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("ex-drill")
    @area = @brand.tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @north = @brand.tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @area)
    create_user(@brand.tenant, org_unit: @north, role: :store, email: "tanger@ex-drill.test", name: "Sara Nord")
    @south_area = @brand.tenant.org_units.create!(name: "Sud", unit_type: "area", parent: @brand.region)
    @south = @brand.tenant.org_units.create!(name: "Agadir", unit_type: "store", parent: @south_area)
    create_user(@brand.tenant, org_unit: @south, role: :store, email: "agadir@ex-drill.test", name: "Omar Sud")
  end

  test "exception rows expose store campaign age assignee and delivery deep link" do
    assignee = @brand.tenant.users.find_by!(email: "tanger@ex-drill.test")
    brief = send_task("Vitrine urgente", stores: [ @north ], priority: "urgent")
    delivery = brief.deliveries.first
    delivery.update!(due_at: 5.hours.ago, awareness: "pending", assignee: assignee)

    board = Vazivo::HqBoard.for(@brand.tenant)
    row = board.exceptions.find { |item| item.org_unit_id == @north.id }

    assert row
    assert_equal "Tanger", row.store_name
    assert_equal "Vitrine urgente", row.campaign
    assert_equal assignee.name, row.owner_name
    assert_equal @area.id, row.area_id
    assert_equal "Nord", row.area_name
    assert row.age_seconds >= 5.hours.to_i
    I18n.with_locale(:en) do
      assert_match(/\d+\s*h/, row.age_label)
    end
    assert_includes row.path, "store-#{@north.id}"
    assert_equal communication_path(brief, anchor: "store-#{@north.id}"), row.path
    refute row.visit_linked?
  end

  test "exceptions sort by severity then priority then oldest age" do
    overdue_old = send_task("Old overdue", stores: [ @north ], priority: "routine")
    overdue_old.deliveries.first.update!(due_at: 3.days.ago, status: "pending", awareness: "received")

    overdue_new = send_task("New overdue", stores: [ @south ], priority: "routine")
    overdue_new.deliveries.first.update!(due_at: 1.hour.ago, status: "pending", awareness: "received")

    redo_brief = send_task("Redo me", stores: [ @south ], priority: "urgent")
    redo_brief.deliveries.first.update!(
      status: "completed",
      completed_at: 1.day.ago,
      awareness: "done",
      verdict: "non_conforme",
      validated_at: 12.hours.ago
    )

    # Latest brief drives the unconfirmed bucket.
    unconfirmed = send_task("Confirm me", stores: [ @north ])
    unconfirmed.deliveries.first.update!(awareness: "pending", created_at: 2.days.ago, due_at: 2.days.from_now)

    kinds = Vazivo::HqBoard.for(@brand.tenant).exceptions.map(&:kind)
    assert_equal "redo", kinds.first
    assert_includes kinds, "unconfirmed"
    assert_equal "unconfirmed", kinds.last
    overdue_rows = Vazivo::HqBoard.for(@brand.tenant).exceptions.select { |row| row.kind == "overdue" }
    assert_operator overdue_rows.size, :>=, 2
    assert_operator overdue_rows.first.age_seconds, :>=, overdue_rows.last.age_seconds
    severity = { "redo" => 0, "overdue" => 1, "unconfirmed" => 2 }
    assert_equal kinds.sort_by { |kind| severity.fetch(kind, 9) }, kinds
  end

  test "area filter keeps only exceptions under that area" do
    north_brief = send_task("Nord late", stores: [ @north ])
    north_brief.deliveries.first.update!(due_at: 2.hours.ago, awareness: "pending")
    south_brief = send_task("Sud late", stores: [ @south ])
    south_brief.deliveries.first.update!(due_at: 2.hours.ago, awareness: "pending")

    board = Vazivo::HqBoard.for(@brand.tenant, area_id: @area.id)
    assert board.areas.map(&:name).sort == %w[Nord Sud]
    assert_equal @area.id, board.area_id
    assert board.exceptions.any?
    assert board.exceptions.all? { |row| row.area_id == @area.id }
    assert_equal [ "Tanger" ], board.exceptions.map(&:store_name).uniq
  end

  test "visit-linked exception deep links to the visit" do
    visit = @brand.tenant.visits.create!(
      org_unit: @north,
      auditor: @brand.hq,
      created_by: @brand.hq,
      planned_at: 1.day.from_now,
      status: "planned"
    )
    brief = send_task("Corrective from visit", stores: [ @north ])
    brief.update!(visit: visit)
    brief.deliveries.first.update!(
      status: "completed",
      completed_at: Time.current,
      awareness: "done",
      verdict: "non_conforme",
      validated_at: Time.current
    )

    row = Vazivo::HqBoard.for(@brand.tenant).exceptions.find { |item| item.kind == "redo" }
    assert row
    assert row.visit_linked?
    assert_equal visit_path(visit), row.path
  end

  private

  def send_task(title, stores:, priority: "routine")
    @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: title,
      body_fr: title,
      format: "task",
      status: "draft",
      priority: priority
    ).tap { |brief| brief.send_to!(stores.map(&:id)) }
  end

  def communication_path(brief, anchor: nil)
    Rails.application.routes.url_helpers.communication_path(brief, anchor: anchor)
  end

  def visit_path(visit)
    Rails.application.routes.url_helpers.visit_path(visit)
  end
end
