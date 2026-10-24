require "test_helper"

class VisitsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("visits-ma")
    @area = @brand.tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @north_store = @brand.tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @area)
    @area_user = create_user(@brand.tenant, org_unit: @area, role: :area)
  end

  def planned_visit(store: @brand.store, auditor: @brand.hq)
    @brand.tenant.visits.create!(org_unit: store, auditor: auditor, planned_at: 3.days.from_now, created_by: @brand.hq)
  end

  test "hq plans a visit and assigns an auditor" do
    sign_in(@brand.hq)

    get new_visit_path
    assert_response :success

    assert_difference -> { @brand.tenant.visits.count }, 1 do
      post visits_path, params: { visit: {
        org_unit_id: @brand.store.id, auditor_id: @brand.hq.id,
        planned_at: "2026-11-02T10:30", notes: "Window check"
      } }
    end

    visit = @brand.tenant.visits.last
    assert_redirected_to visits_path
    assert_equal @brand.hq, visit.auditor
    assert_equal @brand.store, visit.org_unit
    assert_equal @brand.hq, visit.created_by
    assert_equal "planned", visit.status
    assert_equal 10, visit.planned_at.in_time_zone("Africa/Casablanca").hour
    assert_equal 30, visit.planned_at.in_time_zone("Africa/Casablanca").min

    follow_redirect!
    assert_match @brand.store.name, response.body
  end

  test "create without an auditor re-renders the form" do
    sign_in(@brand.hq)

    assert_no_difference -> { Visit.count } do
      post visits_path, params: { visit: { org_unit_id: @brand.store.id, planned_at: "2026-11-02T10:30" } }
    end
    assert_response :unprocessable_entity
  end

  test "hq edits a planned visit" do
    visit = planned_visit
    sign_in(@brand.hq)

    get edit_visit_path(visit)
    assert_response :success

    patch visit_path(visit), params: { visit: { auditor_id: @area_user.id, notes: "Reassigned" } }
    assert_redirected_to visits_path
    assert_equal @area_user, visit.reload.auditor
    assert_equal "Reassigned", visit.notes
  end

  test "hq cancels a visit and it cannot be edited afterwards" do
    visit = planned_visit
    sign_in(@brand.hq)

    patch cancel_visit_path(visit), params: { cancel_reason: "Store closed" }
    assert_redirected_to visits_path
    assert visit.reload.cancelled?
    assert_equal "Store closed", visit.cancel_reason

    get edit_visit_path(visit)
    assert_redirected_to visits_path
    patch visit_path(visit), params: { visit: { notes: "Nope" } }
    assert_nil visit.reload.notes
  end

  test "status filter narrows the list" do
    planned_visit(store: @brand.store)
    cancelled = planned_visit(store: @north_store)
    cancelled.cancel!
    sign_in(@brand.hq)

    get visits_path(status: "cancelled")
    assert_match @north_store.name, response.body
    assert_no_match(/Maarif/, response.body.split("<main").last)
  end

  test "store users cannot manage visits" do
    sign_in(@brand.store_user)

    get visits_path
    assert_redirected_to app_root_path
    assert_no_difference -> { Visit.count } do
      post visits_path, params: { visit: { org_unit_id: @brand.store.id, auditor_id: @brand.hq.id, planned_at: "2026-11-02T10:30" } }
    end
  end

  test "morocco_ops flag gates the visits pages" do
    brand = build_brand("visits-off", features: { morocco_ops: false })
    sign_in(brand.hq)

    get visits_path
    assert_redirected_to app_root_path
  end

  test "visits are scoped to the tenant" do
    other = build_brand("visits-other")
    foreign = other.tenant.visits.create!(org_unit: other.store, auditor: other.hq, planned_at: 2.days.from_now)
    sign_in(@brand.hq)

    get edit_visit_path(foreign)
    assert_response :not_found
    patch cancel_visit_path(foreign)
    assert_response :not_found
    assert_not foreign.reload.cancelled?
  end

  test "hq cannot plan a visit at a store from another tenant" do
    other = build_brand("visits-foreign")
    sign_in(@brand.hq)

    assert_no_difference -> { Visit.count } do
      post visits_path, params: { visit: { org_unit_id: other.store.id, auditor_id: @brand.hq.id, planned_at: "2026-11-02T10:30" } }
    end
    assert_response :unprocessable_entity
  end

  test "area users only see and plan visits for their own stores" do
    own = planned_visit(store: @north_store, auditor: @area_user)
    elsewhere = planned_visit(store: @brand.store)
    sign_in(@area_user)

    get visits_path
    assert_response :success
    assert_match dom_id_for(own), response.body
    assert_no_match(/#{dom_id_for(elsewhere)}/, response.body)
    assert_select "a.app-nav-link[href='#{visits_path}']"
    assert_select "a.app-bottom-nav__link[href='#{visits_path}']"

    get new_visit_path
    assert_response :success
    assert_select "select#visit_org_unit_id option[value='#{@north_store.id}']"
    assert_select "select#visit_org_unit_id option[value='#{@brand.store.id}']", count: 0

    get edit_visit_path(elsewhere)
    assert_response :not_found
    patch visit_path(elsewhere), params: { visit: { notes: "Leak" } }
    assert_response :not_found
    assert_nil elsewhere.reload.notes
    patch cancel_visit_path(elsewhere), params: { cancel_reason: "Nope" }
    assert_response :not_found
    assert_not elsewhere.reload.cancelled?

    assert_no_difference -> { Visit.count } do
      post visits_path, params: { visit: { org_unit_id: @brand.store.id, auditor_id: @area_user.id, planned_at: "2026-11-02T10:30" } }
    end
    assert_response :unprocessable_entity

    assert_difference -> { Visit.count }, 1 do
      post visits_path, params: { visit: { org_unit_id: @north_store.id, auditor_id: @area_user.id, planned_at: "2026-11-02T10:30" } }
    end
    created = @brand.tenant.visits.order(:id).last
    assert_equal @north_store, created.org_unit
    assert_equal @area_user, created.created_by
  end

  test "area users can edit and cancel visits at descendant stores" do
    visit = planned_visit(store: @north_store, auditor: @area_user)
    sign_in(@area_user)

    get edit_visit_path(visit)
    assert_response :success

    patch visit_path(visit), params: { visit: { notes: "Area follow-up", auditor_id: @area_user.id } }
    assert_redirected_to visits_path
    assert_equal "Area follow-up", visit.reload.notes

    patch cancel_visit_path(visit), params: { cancel_reason: "Store closed" }
    assert_redirected_to visits_path
    assert visit.reload.cancelled?
    assert_equal "Store closed", visit.cancel_reason
  end

  test "area users cannot manage visits in a neighbouring area" do
    other_area = @brand.tenant.org_units.create!(name: "Sud", unit_type: "area", parent: @brand.region)
    other_store = @brand.tenant.org_units.create!(name: "Agadir", unit_type: "store", parent: other_area)
    foreign = planned_visit(store: other_store)
    sign_in(@area_user)

    get visits_path
    assert_no_match(/#{dom_id_for(foreign)}/, response.body)
    assert_no_match(/Agadir/, response.body)

    get visit_path(foreign)
    assert_response :not_found
    get edit_visit_path(foreign)
    assert_response :not_found
    patch cancel_visit_path(foreign)
    assert_response :not_found
    assert_not foreign.reload.cancelled?

    assert_no_difference -> { Visit.count } do
      post visits_path, params: { visit: { org_unit_id: other_store.id, auditor_id: @area_user.id, planned_at: "2026-11-02T10:30" } }
    end
    assert_response :unprocessable_entity
  end

  test "visit locales exist in every language" do
    %i[fr en es ar].each do |locale|
      %w[title new edit cancel save statuses.planned statuses.cancelled fields.auditor].each do |key|
        assert I18n.exists?("morocco.visits.#{key}", locale), "missing #{locale} morocco.visits.#{key}"
      end
      assert I18n.exists?("nav.visits", locale)
    end
  end

  private

  def dom_id_for(visit)
    ActionView::RecordIdentifier.dom_id(visit)
  end
end
