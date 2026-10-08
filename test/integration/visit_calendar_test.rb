require "test_helper"

class VisitCalendarTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("calendar-ma")
    @tenant = @brand.tenant
    @area = @tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @north_store = @tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @area)
    @area_user = create_user(@tenant, org_unit: @area, role: :area)
    @zone = Vazivo::Schedule::ZONE
  end

  def visit_on(day, hour: 10, store: @brand.store, auditor: @brand.hq)
    @tenant.visits.create!(org_unit: store, auditor: auditor, planned_at: @zone.parse("#{day} #{hour}:00"), created_by: @brand.hq)
  end

  def calendar_id(visit)
    "calendar_#{ActionView::RecordIdentifier.dom_id(visit)}"
  end

  test "hq sees the month calendar with a link to the visit detail" do
    visit = visit_on("2026-11-12")
    sign_in(@brand.hq)

    get calendar_visits_path(date: "2026-11-05")
    assert_response :success
    assert_select "h2.visit-calendar__title", /November 2026/
    assert_select "[data-date='2026-11-12'] a##{calendar_id(visit)}[href='#{visit_path(visit)}']"

    get visit_path(visit)
    assert_response :success
    assert_match @brand.store.name, response.body
  end

  test "week view shows only that week" do
    inside = visit_on("2026-11-12")
    outside = visit_on("2026-11-20")
    sign_in(@brand.hq)

    get calendar_visits_path(view: "week", date: "2026-11-12")
    assert_response :success
    assert_select "a##{calendar_id(inside)}"
    assert_select "a##{calendar_id(outside)}", count: 0
    assert_select ".visit-calendar__day", count: 7
  end

  test "visits are grouped by Casablanca day" do
    late = visit_on("2026-11-12", hour: 23)
    sign_in(@brand.hq)

    get calendar_visits_path(date: "2026-11-12")
    assert_select "[data-date='2026-11-12'] a##{calendar_id(late)}"
  end

  test "filters by region and auditor" do
    casa = visit_on("2026-11-12", store: @brand.store, auditor: @brand.hq)
    nord = visit_on("2026-11-13", store: @north_store, auditor: @area_user)
    sign_in(@brand.hq)

    get calendar_visits_path(date: "2026-11-05", unit_id: @area.id)
    assert_select "a##{calendar_id(nord)}"
    assert_select "a##{calendar_id(casa)}", count: 0

    get calendar_visits_path(date: "2026-11-05", unit_id: @brand.region.id)
    assert_select "a##{calendar_id(nord)}"
    assert_select "a##{calendar_id(casa)}"

    get calendar_visits_path(date: "2026-11-05", auditor_id: @brand.hq.id)
    assert_select "a##{calendar_id(casa)}"
    assert_select "a##{calendar_id(nord)}", count: 0
  end

  test "area users only see visits at their descendant stores" do
    own = visit_on("2026-11-12", store: @north_store, auditor: @area_user)
    elsewhere = visit_on("2026-11-13", store: @brand.store)
    sign_in(@area_user)

    get calendar_visits_path(date: "2026-11-05")
    assert_response :success
    assert_select "a##{calendar_id(own)}"
    assert_select "a##{calendar_id(elsewhere)}", count: 0
    assert_select "select#unit_id option", text: @area.name

    get calendar_visits_path(date: "2026-11-05", unit_id: @brand.region.id)
    assert_select "a##{calendar_id(own)}"
    assert_select "a##{calendar_id(elsewhere)}", count: 0

    get visit_path(elsewhere)
    assert_response :not_found
  end

  test "other tenants visits never appear" do
    other = build_brand("calendar-other")
    foreign = other.tenant.visits.create!(org_unit: other.store, auditor: other.hq, planned_at: @zone.parse("2026-11-12 10:00"))
    sign_in(@brand.hq)

    get calendar_visits_path(date: "2026-11-05", auditor_id: other.hq.id)
    assert_select "a##{calendar_id(foreign)}", count: 0

    get visit_path(foreign)
    assert_response :not_found
  end

  test "invalid date and view fall back to defaults" do
    sign_in(@brand.hq)

    get calendar_visits_path(date: "nope", view: "year")
    assert_response :success
    assert_select ".visit-calendar__grid--month"
  end

  test "store users and disabled morocco_ops are blocked" do
    sign_in(@brand.store_user)
    get calendar_visits_path
    assert_redirected_to app_root_path

    off = build_brand("calendar-off", features: { morocco_ops: false })
    sign_in(off.hq)
    get calendar_visits_path
    assert_redirected_to app_root_path
  end

  test "calendar locales exist in every language" do
    %i[fr en es ar].each do |locale|
      %w[title lede prev next today views.month views.week filter_unit filter_auditor empty].each do |key|
        assert I18n.exists?("morocco.visits.calendar.#{key}", locale), "missing #{locale} morocco.visits.calendar.#{key}"
      end
    end
  end
end
