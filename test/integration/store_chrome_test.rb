require "test_helper"

class StoreChromeTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("store-chrome")
  end

  test "store nav never exposes HQ compose or board actions" do
    sign_in(@brand.store_user)

    assert_select "a.app-sidebar__compose", count: 0
    assert_select "a.app-nav-link[href=?]", new_communication_path, count: 0
    assert_select "a.app-nav-link[href=?]", playbooks_path, count: 0
    assert_select "a.app-nav-link[href=?]", billing_path, count: 0
    assert_select "a.app-nav-link[href=?]", org_units_path, count: 0
    assert_select "a.app-nav-link[href=?]", checklists_path, count: 0
    assert_select "a.app-nav-link[href=?]", templates_path, count: 0
    assert_select "a.app-nav-link[href=?]", reports_path, count: 0
    assert_select "a.app-nav-link[href=?]", visits_path, count: 0
    assert_select "a.app-nav-link[href=?]", communications_path, count: 0
    assert_select "a.app-nav-link[href=?]", admin_root_path, count: 0

    assert_select "a.app-nav-link[href=?]", app_root_path
    assert_select "a.app-nav-link[href=?]", ranking_path
    assert_select "a.app-nav-link[href=?]", my_tasks_path
    assert_select "a.app-nav-link[href=?]", newsfeeds_path
    assert_select "a.app-nav-link[href=?]", calendar_visits_path
    assert_select ".app-bottom-nav"
    assert_select ".hq-board", count: 0
  end

  test "store today is radar not the HQ exception board" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Brief rayon",
      body_fr: "Mettre en avant",
      format: "task",
      status: "draft"
    )
    brief.send_to!([ @brand.store.id ])

    sign_in(@brand.store_user)
    assert_response :success
    assert_select ".radar-hero"
    assert_select ".hq-board", count: 0
    assert_select "a[href=?]", new_communication_path, count: 0
    assert_select "a[href=?]", playbooks_path, count: 0
    assert_select "a[href=?]", billing_path, count: 0
  end

  test "store cannot reach HQ surfaces" do
    sign_in(@brand.store_user)

    hq_paths = [
      new_communication_path,
      communications_path,
      playbooks_path,
      campaigns_playbooks_path,
      closing_reports_playbooks_path,
      billing_path,
      org_units_path,
      checklists_path,
      templates_path,
      task_templates_path,
      reports_path,
      visits_path,
      new_visit_path
    ]

    hq_paths.each do |path|
      get path
      assert_redirected_to app_root_path, "expected #{path} to be blocked for store role"
    end

    patch ramadan_path
    assert_redirected_to app_root_path

    get admin_root_path
    assert_redirected_to app_root_path
  end

  test "store inbox stays on the signed-in store only" do
    other = @brand.tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: @brand.region)
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Shared campaign brief",
      body_fr: "x",
      format: "task",
      status: "draft"
    )
    brief.send_to!([ @brand.store.id, other.id ])
    own_delivery = brief.deliveries.find_by!(org_unit: @brand.store)
    foreign_delivery = brief.deliveries.find_by!(org_unit: other)

    sign_in(@brand.store_user)
    get inbox_index_path
    assert_response :success
    assert_select "a[href=?]", inbox_path(own_delivery)
    assert_select "a[href=?]", inbox_path(foreign_delivery), count: 0

    get inbox_path(foreign_delivery)
    assert_response :not_found
  end

  test "permission matrix keeps compose and board capabilities HQ-only" do
    assert Membership.allows?("hq", :compose)
    assert Membership.allows?("hq", :playbooks)
    assert Membership.allows?("hq", :billing)
    assert Membership.allows?("hq", :manage_org)
    assert_not Membership.allows?("store", :compose)
    assert_not Membership.allows?("store", :monitor)
    assert_not Membership.allows?("store", :visits)
    assert_not Membership.allows?("store", :playbooks)
    assert_not Membership.allows?("store", :billing)
    assert_not Membership.allows?("store", :manage_org)
    assert_not Membership.allows?("store", :reports)
    assert Membership.allows?("store", :execute)
  end
end
