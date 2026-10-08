require "test_helper"

class VazivoRecurrenceTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("recurring")
    @store_b = @brand.tenant.org_units.create!(name: "Gueliz", unit_type: "store", parent: @brand.region)
    @today = Date.new(2026, 10, 7) # Wednesday
  end

  test "normalize keeps only the fields of the chosen frequency" do
    assert_equal({}, Vazivo::Recurrence.normalize(frequency: "none"))
    assert_equal({ "frequency" => "daily" }, Vazivo::Recurrence.normalize(frequency: "daily", interval: "3"))
    assert_equal(
      { "frequency" => "weekly", "weekdays" => [ 1, 3 ] },
      Vazivo::Recurrence.normalize(frequency: "weekly", weekdays: [ "3", "1", "", "9" ])
    )
    assert_equal(
      { "frequency" => "custom", "interval" => 4, "ends_on" => "2026-12-31" },
      Vazivo::Recurrence.normalize(frequency: "custom", interval: "4", ends_on: "2026-12-31")
    )
  end

  test "next_on handles daily, weekly, custom, and the end date" do
    assert_equal Date.new(2026, 10, 8), Vazivo::Recurrence.next_on({ "frequency" => "daily" }, @today)
    assert_equal Date.new(2026, 10, 12), Vazivo::Recurrence.next_on({ "frequency" => "weekly", "weekdays" => [ 1 ] }, @today)
    assert_equal Date.new(2026, 10, 9), Vazivo::Recurrence.next_on({ "frequency" => "weekly", "weekdays" => [ 5, 1 ] }, @today)
    assert_equal Date.new(2026, 10, 10), Vazivo::Recurrence.next_on({ "frequency" => "custom", "interval" => 3 }, @today)
    assert_nil Vazivo::Recurrence.next_on({ "frequency" => "daily", "ends_on" => "2026-10-07" }, @today)
  end

  test "rule validation rejects incomplete rules and non task briefs" do
    brief = build_brief(rule: { "frequency" => "weekly", "weekdays" => [] })
    assert_not brief.valid?

    brief = build_brief(rule: { "frequency" => "custom", "interval" => 0 })
    assert_not brief.valid?

    news = build_brief(rule: { "frequency" => "daily" }, format: "news")
    assert news.valid?
    assert_empty news.recurrence_rule
  end

  test "sending a recurring brief arms the next occurrence" do
    brief = send_recurring({ "frequency" => "daily" })

    assert brief.recurring?
    assert brief.recurrence_active?
    assert_equal Vazivo::Schedule.now.to_date + 1, brief.recurrence_next_on
  end

  test "spawning clones the brief and its questions to the same stores" do
    brief = send_recurring({ "frequency" => "daily" }, store_ids: [ @brand.store.id, @store_b.id ], with_question: true)
    complete_all(brief)
    tomorrow = brief.recurrence_next_on

    occurrence = nil
    assert_difference -> { Delivery.count }, 2 do
      occurrence = Vazivo::Recurrence.spawn!(brief, today: tomorrow)
    end

    assert occurrence.sent?
    assert_equal brief, occurrence.recurrence_parent
    assert_equal tomorrow, occurrence.occurrence_on
    assert_equal brief.tenant_id, occurrence.tenant_id
    assert_equal brief.deliveries.pluck(:org_unit_id).sort, occurrence.deliveries.pluck(:org_unit_id).sort
    assert_equal %w[Done?], occurrence.communication_questions.map(&:title_fr)
    assert_not occurrence.recurring?
    assert_equal tomorrow + 1, brief.reload.recurrence_next_on
  end

  test "occurrence keeps the clock time of the source deadline on its own date" do
    brief = send_recurring({ "frequency" => "daily" })
    brief.update_column(:due_at, Vazivo::Schedule::ZONE.local(2026, 10, 7, 17, 30))
    complete_all(brief)

    occurrence = Vazivo::Recurrence.spawn!(brief, today: brief.recurrence_next_on)
    local = occurrence.due_at.in_time_zone(Vazivo::Schedule::ZONE)

    assert_equal occurrence.occurrence_on, local.to_date
    assert_equal [ 17, 30 ], [ local.hour, local.min ]
  end

  test "does not duplicate work a store still has in flight" do
    brief = send_recurring({ "frequency" => "daily" }, store_ids: [ @brand.store.id, @store_b.id ])
    brief.deliveries.find_by!(org_unit: @store_b).complete!

    occurrence = nil
    assert_difference -> { Delivery.count }, 1 do
      occurrence = Vazivo::Recurrence.spawn!(brief, today: brief.recurrence_next_on)
    end

    assert_equal [ @store_b.id ], occurrence.deliveries.pluck(:org_unit_id)
  end

  test "skips the occurrence entirely when every store is still busy but keeps the schedule" do
    brief = send_recurring({ "frequency" => "daily" })
    due_on = brief.recurrence_next_on

    assert_no_difference -> { Communication.count } do
      assert_nil Vazivo::Recurrence.spawn!(brief, today: due_on)
    end
    assert_equal due_on + 1, brief.reload.recurrence_next_on
  end

  test "running the scheduler twice on the same day creates one occurrence" do
    brief = send_recurring({ "frequency" => "daily" })
    complete_all(brief)
    day = brief.recurrence_next_on

    first = Vazivo::Recurrence.spawn_all!(today: day)
    second = Vazivo::Recurrence.spawn_all!(today: day)

    assert_equal 1, first.size
    assert_empty second
    assert_equal 1, brief.occurrences.count
  end

  test "a long outage creates only the latest missed occurrence" do
    brief = send_recurring({ "frequency" => "daily" })
    complete_all(brief)
    later = brief.recurrence_next_on + 5

    occurrence = Vazivo::Recurrence.spawn!(brief, today: later)

    assert_equal later, occurrence.occurrence_on
    assert_equal 1, brief.occurrences.count
    assert_equal later + 1, brief.reload.recurrence_next_on
  end

  test "the series ends after its end date" do
    brief = send_recurring({ "frequency" => "daily", "ends_on" => (Vazivo::Schedule.now.to_date + 1).iso8601 })
    complete_all(brief)

    Vazivo::Recurrence.spawn!(brief, today: brief.recurrence_next_on)

    assert_nil brief.reload.recurrence_next_on
    assert_not brief.recurrence_active?
  end

  test "stopped series are not spawned" do
    brief = send_recurring({ "frequency" => "daily" })
    complete_all(brief)
    day = brief.recurrence_next_on
    Vazivo::Recurrence.stop!(brief)

    assert_empty Vazivo::Recurrence.spawn_all!(today: day)
  end

  test "scheduler job spawns for every tenant and keeps tenants apart" do
    other = build_brand("recurring-other")
    mine = send_recurring({ "frequency" => "daily" })
    theirs = send_recurring({ "frequency" => "daily" }, brand: other)
    [ mine, theirs ].each { |brief| complete_all(brief) }
    day = mine.recurrence_next_on

    travel_to Vazivo::Schedule::ZONE.local(day.year, day.month, day.day, 8, 0) do
      assert_difference -> { Communication.count }, 2 do
        RecurringTaskJob.perform_now
      end
    end

    assert_equal [ mine.tenant_id ], mine.occurrences.map(&:tenant_id).uniq
    assert_equal [ theirs.tenant_id ], theirs.occurrences.map(&:tenant_id).uniq
    assert_equal [ other.store.id ], theirs.occurrences.first.deliveries.pluck(:org_unit_id)
  end

  test "stores only see the newest instance of a series" do
    brief = send_recurring({ "frequency" => "daily" })
    old_delivery = brief.deliveries.first
    old_delivery.complete!
    occurrence = Vazivo::Recurrence.spawn!(brief, today: brief.recurrence_next_on)

    visible = Delivery.current_instances.where(org_unit: @brand.store).pluck(:id)

    assert_equal [ occurrence.deliveries.first.id ], visible
    assert_not_includes visible, old_delivery.id
  end

  test "non recurring deliveries stay visible next to a series" do
    plain = send_task("One off")
    brief = send_recurring({ "frequency" => "daily" })

    visible = Delivery.current_instances.where(org_unit: @brand.store).pluck(:id)

    assert_includes visible, plain.deliveries.first.id
    assert_includes visible, brief.deliveries.first.id
  end

  private

  def build_brief(rule:, format: "task", brand: @brand)
    brand.tenant.communications.new(
      author: brand.hq, title_fr: "Facing", body_fr: "Check facing.", format: format, status: "draft", recurrence_rule: rule
    )
  end

  def send_task(title, store_ids: [ @brand.store.id ])
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Do it.", format: "task", status: "draft"
    )
    brief.send_to!(store_ids)
    brief
  end

  def send_recurring(rule, store_ids: nil, with_question: false, brand: @brand)
    store_ids ||= [ brand.store.id ]
    brief = build_brief(rule: rule, brand: brand)
    brief.save!
    brief.communication_questions.create!(title_fr: "Done?", question_type: "short_text", position: 0) if with_question
    brief.send_to!(store_ids)
    brief.reload
  end

  def complete_all(brief)
    brief.deliveries.each(&:complete!)
  end
end
