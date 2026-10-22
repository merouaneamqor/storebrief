require "test_helper"

class RetailCalendarTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("retail-calendar")
    @tenant = @brand.tenant
    @area = @tenant.org_units.create!(name: "North", unit_type: "area", parent: @brand.region)
    @north = @tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @area)
    @area_user = create_user(@tenant, org_unit: @area, role: :area)
    @zone = Vazivo::Schedule::ZONE
    @visit = @tenant.visits.create!(org_unit: @brand.store, auditor: @brand.hq, planned_at: @zone.parse("2026-11-12 10:00"))
    @task = create_task(@brand.store, "Window display")
    @campaign = create_campaign(@brand.store)
  end

  def create_task(store, title, day: "2026-11-12", parent: nil, status: "sent")
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Instructions",
      format: "task", status: status, recurrence_parent: parent
    )
    brief.deliveries.create!(org_unit: store, due_at: @zone.parse("#{day} 18:00"))
  end

  def create_campaign(store)
    playbook = Playbook.ensure_defaults!(@tenant).first
    checklist = @tenant.checklists.create!(
      author: @brand.hq, playbook: playbook, title_fr: "Winter campaign",
      starts_on: "2026-11-10", campaign_on: "2026-11-15", status: "sent"
    )
    checklist.checklist_deliveries.create!(org_unit: store, due_at: @zone.parse("2026-11-15 18:00"))
  end

  def event_id(record, milestone = nil)
    "calendar_#{ActionView::RecordIdentifier.dom_id(record)}#{"_#{milestone}" if milestone}"
  end

  test "hq calendar combines visits task deadlines and both campaign milestones" do
    sign_in(@brand.hq)
    get calendar_visits_path(date: "2026-11-12")
    assert_response :success
    assert_select "[data-date='2026-11-12'] a##{event_id(@visit)}[href='#{visit_path(@visit)}']"
    assert_select "[data-date='2026-11-12'] a##{event_id(@task)}[href='#{communication_path(@task.communication, anchor: "store-#{@brand.store.id}")}']"
    assert_select "[data-date='2026-11-10'] a##{event_id(@campaign, 'starts_on')}"
    assert_select "[data-date='2026-11-15'] a##{event_id(@campaign, 'campaign_on')}"
  end

  test "type filters and navigation preserve current filters" do
    sign_in(@brand.hq)
    %w[visit task campaign].each do |kind|
      get calendar_visits_path(date: "2026-11-12", type: kind, store_id: @brand.store.id)
      assert_response :success
      assert_select "[data-event-type='#{kind}']"
      (Vazivo::RetailCalendar::TYPES - [ kind ]).each do |other|
        assert_select "[data-event-type='#{other}']", count: 0
      end
      assert_select "a[rel='next']" do |links|
        query = Rack::Utils.parse_nested_query(URI.parse(links.first["href"]).query)
        assert_equal kind, query["type"]
        assert_equal @brand.store.id.to_s, query["store_id"]
      end
    end
  end

  test "store and area filters apply to every event type" do
    north_task = create_task(@north, "North deadline")
    north_campaign = create_campaign(@north)
    sign_in(@brand.hq)

    [ { unit_id: @area.id }, { store_id: @north.id } ].each do |filters|
      get calendar_visits_path(filters.merge(date: "2026-11-12"))
      assert_select "##{event_id(north_task)}"
      assert_select "##{event_id(north_campaign, 'starts_on')}"
      assert_select "##{event_id(@task)}", count: 0
      assert_select "##{event_id(@campaign, 'starts_on')}", count: 0
      assert_select "##{event_id(@visit)}", count: 0
    end
  end

  test "area calendar cannot escape descendant stores through filters" do
    own_task = create_task(@north, "North deadline")
    own_campaign = create_campaign(@north)
    sign_in(@area_user)
    get calendar_visits_path(date: "2026-11-12", store_id: @brand.store.id, unit_id: @brand.region.id)
    assert_response :success
    assert_select "a##{event_id(own_task)}"
    assert_select "a##{event_id(own_campaign, 'starts_on')}[href='#{store_path(@north)}']"
    assert_select "##{event_id(@task)}", count: 0
    assert_select "##{event_id(@campaign, 'starts_on')}", count: 0
    assert_select "select#store_id option[value='#{@brand.store.id}']", count: 0
  end

  test "store sees only its own calendar and can open its own work without visit management" do
    other_task = create_task(@north, "Other store deadline")
    other_campaign = create_campaign(@north)
    sign_in(@brand.store_user)
    get calendar_visits_path(date: "2026-11-12", store_id: @north.id, unit_id: @area.id)
    assert_response :success
    assert_select "div##{event_id(@visit)}"
    assert_select "a[href='#{visit_path(@visit)}']", count: 0
    assert_select "a##{event_id(@task)}[href='#{inbox_path(@task)}']"
    assert_select "a##{event_id(@campaign, 'campaign_on')}[href='#{checklists_delivery_path(@campaign)}']"
    assert_select "##{event_id(other_task)}", count: 0
    assert_select "##{event_id(other_campaign, 'starts_on')}", count: 0
    assert_select "select#store_id, select#unit_id, a[href='#{new_visit_path}']", count: 0

    get visit_path(@visit)
    assert_redirected_to app_root_path
  end

  test "tasks and campaigns from another tenant are excluded even with forged filters" do
    other = build_brand("retail-calendar-other")
    foreign_brief = other.tenant.communications.create!(author: other.hq, title_fr: "Secret", body_fr: "Private", format: "task", status: "sent")
    foreign_task = foreign_brief.deliveries.create!(org_unit: other.store, due_at: @task.due_at)
    foreign_checklist = other.tenant.checklists.create!(author: other.hq, title_fr: "Secret campaign", status: "sent", playbook: Playbook.ensure_defaults!(other.tenant).first, campaign_on: "2026-11-15")
    foreign_campaign = foreign_checklist.checklist_deliveries.create!(org_unit: other.store)
    sign_in(@brand.hq)

    get calendar_visits_path(date: "2026-11-12", store_id: other.store.id, unit_id: other.region.id)
    assert_response :success
    assert_select "##{event_id(@task)}"
    assert_select "##{event_id(foreign_task)}", count: 0
    assert_select "##{event_id(foreign_campaign, 'campaign_on')}", count: 0
    assert_select "select#store_id option[value='#{other.store.id}']", count: 0
  end

  test "week view includes assigned recurring occurrences on their actual dates and excludes drafts" do
    occurrence = create_task(@brand.store, "Weekly window", day: "2026-11-13", parent: @task.communication)
    outside = create_task(@brand.store, "Next week", day: "2026-11-20", parent: @task.communication)
    draft = create_task(@brand.store, "Unsent draft", status: "draft")
    sign_in(@brand.hq)

    get calendar_visits_path(date: "2026-11-12", view: "week")
    assert_select "[data-date='2026-11-12'] ##{event_id(@task)}"
    assert_select "[data-date='2026-11-13'] ##{event_id(occurrence)}"
    assert_select "##{event_id(outside)}", count: 0
    assert_select "##{event_id(draft)}", count: 0
    assert_select ".visit-calendar__day", count: 7
  end

  test "task deadlines keep their store local date near midnight" do
    @task.update!(due_at: @zone.local(2026, 11, 13, 0, 30).utc)
    sign_in(@brand.hq)
    get calendar_visits_path(date: "2026-11-12")
    assert_select "[data-date='2026-11-13'] ##{event_id(@task)}"
  end

  test "disabled modules do not leak their calendar entries" do
    @tenant.update!(features: @tenant.features.merge("briefs" => false, "checklists" => false))
    sign_in(@brand.hq)
    get calendar_visits_path(date: "2026-11-12")
    assert_response :success
    assert_select "##{event_id(@visit)}"
    assert_select "[data-event-type='task'], [data-event-type='campaign']", count: 0
  end

  test "French Arabic RTL and other supported locales render without missing copy" do
    sign_in(@brand.store_user)
    %w[fr ar en es].each do |locale|
      get calendar_visits_path(date: "2026-11-12", locale: locale)
      assert_response :success
      assert_select "html[dir='#{locale == 'ar' ? 'rtl' : 'ltr'}']"
      assert_select "h1", text: I18n.t("morocco.retail_calendar.title", locale: locale)
      assert_select ".translation_missing", count: 0
    end
  end
end
