require "test_helper"

class VazivoOpsTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("vazivo-ops")
  end

  test "ramadan mode moves a morning task to opening time" do
    @brand.tenant.update!(ramadan_mode: true, ramadan_opens_at: "12:00", opens_at: "09:00")
    due = Vazivo::Schedule.adjust(
      @brand.tenant,
      Vazivo::Schedule::ZONE.local(2026, 3, 10, 10, 0)
    )

    assert_equal 12, due.hour
    assert_equal 0, due.min
  end

  test "an overdue task climbs from the store manager to head office" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Stock chaussures",
      body_fr: "Vérifier le stock.",
      format: "task",
      status: "draft"
    )
    brief.send_to!([ @brand.store.id ])
    delivery = brief.deliveries.first
    delivery.update!(due_at: 73.hours.ago, created_at: 80.hours.ago)

    Vazivo::Escalation.sweep!(@brand.tenant)

    delivery.reload
    assert_equal 3, delivery.escalation_level
    assert_equal %w[store_manager area_manager hq], delivery.escalation_events.order(:level).pluck(:notified_role)
  end

  test "work without a deadline is not late and is not chased" do
    brief = send_task("Sans échéance")
    delivery = brief.deliveries.first
    delivery.update!(due_at: nil, created_at: 5.days.ago, escalation_level: 0)

    assert_not delivery.late?
    Vazivo::Escalation.sweep!(@brand.tenant)
    assert_equal 0, delivery.reload.escalation_level
    assert_equal 0, delivery.escalation_events.count
  end

  test "backfill stamps an owner and an end-of-day deadline" do
    brief = send_task("À rattraper")
    delivery = brief.deliveries.first
    delivery.update!(assignee: nil, due_at: nil)

    Vazivo::Assignment.backfill!(@brand.tenant)

    delivery.reload
    assert_equal @brand.store_user, delivery.assignee
    assert delivery.due_at.present?
  end

  test "ranking crowns the store that actually finished" do
    other = @brand.tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: @brand.region)
    done = send_task("Vitrine A")
    done.deliveries.first.update!(status: "completed", completed_at: Time.current, awareness: "done", verdict: "conforme")
    send_task("Vitrine B", store: other)

    ranking = Vazivo::Ranking.for(@brand.tenant)
    assert_equal @brand.store, ranking.podium.first.store
    assert_equal 100, ranking.podium.first.percent
    assert_equal @brand.store, ranking.awards[:vm].store
  end

  test "hq board merges exceptions by severity" do
    brief = send_task("À confirmer")
    delivery = brief.deliveries.first
    delivery.update!(due_at: 1.hour.ago, awareness: "pending")

    board = Vazivo::HqBoard.for(@brand.tenant)
    assert board.exceptions.any?
    assert_includes board.exceptions.map(&:kind), "unconfirmed"
    severity = { "redo" => 0, "overdue" => 1, "unconfirmed" => 2 }
    kinds = board.exceptions.map(&:kind)
    assert_equal kinds.sort_by { |k| severity.fetch(k, 9) }, kinds

    today = Vazivo::Schedule.now.to_date
    assert_equal today.day, board.trend.points.size
    assert_equal today.end_of_month.day, board.trend.span
    assert_equal 14, board.sparks.fetch("on_track").points.size
    assert_equal 14, board.sparks.fetch("decisions").points.size
    assert_includes board.activity.map(&:kind), "open"
    assert_equal @brand.store, board.leaders.first.store
  end

  private

  def send_task(title, store: @brand.store)
    @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: title,
      body_fr: title,
      format: "task",
      status: "draft"
    ).tap { |brief| brief.send_to!([ store.id ]) }
  end
end
