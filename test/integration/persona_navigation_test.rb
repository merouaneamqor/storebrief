require "test_helper"

class PersonaNavigationTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("persona-nav", features: { morocco_ops: true, knowledge_base: true })
  end

  test "read-only HQ is offered monitoring and reports without unavailable administrative actions" do
    restrict(@brand.hq, "hq", %w[monitor reports])
    sign_in(@brand.hq)
    %w[fr ar].each do |locale|
      get app_root_path(locale: locale)
      assert_response :success
      assert_select ".app-sidebar a[href=?]", communications_path
      assert_select ".app-sidebar a[href=?]", reports_path
      [ new_communication_path, billing_path, org_units_path, playbooks_path,
        visits_path, audit_history_path, templates_path, checklists_path,
        admin_root_path, oidc_settings_path ].each do |path|
        assert_select "a[href=?]", path, count: 0, message: "Read-only HQ must not be sent to denied #{path}"
      end
      assert_select "form[action=?]", ramadan_path, count: 0
      assert_select ".hq-status-strip__tile", count: 3
      assert_select ".hq-status-strip__tile[href]", count: 0
    end
  end

  test "inbox-only store can open news and knowledge but never task execution" do
    restrict(@brand.store_user, "store", %w[inbox])
    sign_in(@brand.store_user)
    get app_root_path
    assert_response :success
    assert_select ".app-sidebar a[href=?]", newsfeeds_path
    assert_select ".app-sidebar a[href=?]", kb_articles_path
    [ my_tasks_path, vm_missions_path, incident_tickets_path ].each do |path|
      assert_select ".app-sidebar a[href=?], .app-bottom-nav a[href=?]", path, path, count: 0
    end
  end

  test "monitor-only area does not see visits or report-only ranking" do
    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    restrict(area, "area", %w[monitor])
    sign_in(area)
    get app_root_path
    assert_response :success
    assert_select ".app-sidebar a[href=?]", communications_path
    [ visits_path, calendar_visits_path, audit_history_path, ranking_path ].each do |path|
      assert_select ".app-sidebar a[href=?], .app-bottom-nav a[href=?]", path, path, count: 0
    end
  end

  test "built-in HQ retains compose and administration while disabled modules disappear" do
    sign_in(@brand.hq)
    get app_root_path
    assert_response :success
    assert_select ".app-sidebar a[href=?]", new_communication_path
    assert_select ".app-sidebar a[href=?]", billing_path
    @brand.tenant.update!(features: @brand.tenant.features.merge("briefs" => false, "checklists" => false, "reports" => false, "knowledge_base" => false))
    get app_root_path
    assert_response :success
    [ communications_path, new_communication_path, playbooks_path, checklists_path,
      templates_path, reports_path, kb_articles_path ].each do |path|
      assert_select ".app-sidebar a[href=?]", path, count: 0
    end
  end

  private

  def restrict(user, base_role, capabilities)
    role = @brand.tenant.tenant_roles.create!(name: "#{base_role} restricted", base_role: base_role, capabilities: capabilities)
    user.memberships.first.update!(tenant_role: role)
  end
end
