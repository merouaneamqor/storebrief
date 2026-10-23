require "test_helper"

class TenantRolesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("roles-ui", features: { morocco_ops: true })
    @other = build_brand("roles-foreign")
    @area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    @role = @brand.tenant.tenant_roles.create!(name: "Read only", base_role: "area", capabilities: %w[monitor reports])
  end

  test "built-in HQ edits localized matrix and assigns compatible memberships" do
    sign_in(@brand.hq)
    %w[fr ar].each do |locale|
      get tenant_roles_path(locale: locale)
      assert_response :success
      assert_select "h1", text: I18n.t("tenant_roles.title", locale: locale)
      assert_select "input[name='tenant_role[capabilities][]']"
    end
    post tenant_roles_path, params: { tenant_role: { name: "Visits only", base_role: "area", capabilities: [ "visits" ] } }
    role = @brand.tenant.tenant_roles.find_by!(name: "Visits only")
    membership = @area.memberships.first
    post assign_tenant_roles_path, params: { membership_id: membership.id, tenant_role_id: role.id }
    assert_equal role.id, membership.reload.tenant_role_id
    patch tenant_role_path(role), params: { tenant_role: { name: "No permissions", capabilities: [ "" ] } }
    assert_empty role.reload.capabilities
    new_member = create_user(@brand.tenant, org_unit: @brand.store, role: :store, email: "extra@roles-ui.test")
    post assign_tenant_roles_path, params: { user_id: new_member.id, org_unit_id: @brand.region.id, tenant_role_id: role.id }
    assert_equal role.id, new_member.memberships.find_by!(org_unit: @brand.region).tenant_role_id
  end

  test "area and store cannot edit matrix or promote themselves" do
    [ @area, @brand.store_user ].each do |user|
      sign_in(user)
      get tenant_roles_path
      assert_redirected_to app_root_path
      assert_no_difference "TenantRole.count" do
        post tenant_roles_path, params: { tenant_role: { name: "Admin", base_role: "hq", capabilities: [ "admin" ] } }
      end
      post assign_tenant_roles_path, params: { membership_id: user.memberships.first.id, tenant_role_id: @role.id }
      assert_redirected_to app_root_path
      assert_nil user.memberships.first.reload.tenant_role_id
    end
  end

  test "HQ cannot touch foreign roles or memberships, default admins, or inject capabilities" do
    foreign = @other.tenant.tenant_roles.create!(name: "Foreign", base_role: "store", capabilities: [ "inbox" ])
    sign_in(@brand.hq)
    patch tenant_role_path(foreign), params: { tenant_role: { name: "Stolen" } }
    assert_response :not_found
    post assign_tenant_roles_path, params: { membership_id: @other.store_user.memberships.first.id, tenant_role_id: @role.id }
    assert_response :not_found
    post assign_tenant_roles_path, params: { membership_id: @area.memberships.first.id, tenant_role_id: foreign.id }
    assert_response :not_found
    post assign_tenant_roles_path, params: { membership_id: @brand.hq.memberships.first.id, tenant_role_id: @role.id }
    assert_nil @brand.hq.memberships.first.reload.tenant_role_id
    assert_no_difference "TenantRole.count" do
      post tenant_roles_path, params: { tenant_role: { name: "Injected", base_role: "area", capabilities: %w[admin billing] } }
    end
    assert_response :unprocessable_entity
  end

  test "attenuated area read works while visits and HQ writes are denied" do
    @area.memberships.first.update!(tenant_role: @role)
    sign_in(@area)
    get communications_path
    assert_response :success
    get visits_path
    assert_redirected_to app_root_path
    assert_no_difference "Communication.count" do
      post communications_path, params: { communication: { title_fr: "Forbidden", body_fr: "X", format: "task" } }
    end
    assert_redirected_to app_root_path
    get tenant_roles_path
    assert_redirected_to app_root_path
  end

  test "custom HQ cannot bypass capability gates or regional scope" do
    role = @brand.tenant.tenant_roles.create!(name: "Scoped HQ", base_role: "hq", capabilities: %w[monitor compose])
    @brand.hq.memberships.first.update!(tenant_role: role)
    sign_in(@brand.hq)
    get communications_path
    assert_response :success
    get new_communication_path
    assert_response :success
    get billing_path
    assert_redirected_to app_root_path
    get tenant_roles_path
    assert_redirected_to app_root_path
    @brand.tenant.org_units.create!(name: "Other root", unit_type: "region")
    get new_communication_path
    assert_redirected_to app_root_path
    get visits_path
    assert_redirected_to app_root_path
  end

  test "custom store inbox remains scoped while execute can be removed" do
    role = @brand.tenant.tenant_roles.create!(name: "Inbox only", base_role: "store", capabilities: [ "inbox" ])
    @brand.store_user.memberships.first.update!(tenant_role: role)
    sign_in(@brand.store_user)
    get inbox_index_path
    assert_response :success
    get newsfeeds_path
    assert_response :success
    get calendar_visits_path
    assert_response :success
    get my_tasks_path
    assert_redirected_to app_root_path
    get checklists_deliveries_path
    assert_redirected_to app_root_path
    post sync_checklist_responses_path, params: { responses: [] }
    assert_redirected_to app_root_path
    role.update!(capabilities: [])
    get inbox_index_path
    assert_redirected_to app_root_path
    get newsfeeds_path
    assert_redirected_to app_root_path
    get calendar_visits_path
    assert_redirected_to app_root_path
  end

  test "scoped custom HQ reports include own subtree and exclude sibling stores" do
    role = @brand.tenant.tenant_roles.create!(name: "Regional reporter", base_role: "hq", capabilities: %w[reports monitor])
    @brand.hq.memberships.first.update!(tenant_role: role)
    other_region = @brand.tenant.org_units.create!(name: "Hidden Region", unit_type: "region")
    other_store = @brand.tenant.org_units.create!(name: "Hidden Store", unit_type: "store", parent: other_region)
    [ @brand.store, other_store ].each do |store|
      brief = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Scoped brief", body_fr: "Do it", format: "task", status: "sent")
      brief.deliveries.create!(org_unit: store, status: "pending").update_column(:created_at, Time.zone.parse("2026-01-10 12:00"))
    end
    sign_in(@brand.hq)
    get reports_path, params: { from: "2026-01-01", to: "2026-01-31" }
    assert_response :success
    assert_select "td", text: @brand.store.name
    assert_no_match "Hidden Store", response.body
  end
  test "a visits-only area role lands on its permitted workflow" do
    role = @brand.tenant.tenant_roles.create!(name: "Visits only", base_role: "area", capabilities: [ "visits" ])
    @area.memberships.first.update!(tenant_role: role)
    sign_in(@area)
    get app_root_path
    assert_redirected_to calendar_visits_path
    follow_redirect!
    assert_response :success
  end
  test "removed inbox permission blocks every store feed mutation" do
    role = @brand.tenant.tenant_roles.create!(name: "No inbox", base_role: "store", capabilities: [ "execute" ])
    @brand.store_user.memberships.first.update!(tenant_role: role)
    sign_in(@brand.store_user)
    assert_no_difference [ "FeedPost.count", "FeedComment.count", "FeedReaction.count" ] do
      post feed_posts_path, params: { body: "Forbidden post" }
      assert_redirected_to app_root_path
      post feed_comments_path, params: { subject_type: "Delivery", subject_id: 0, body: "Forbidden comment" }
      assert_redirected_to app_root_path
      post feed_reactions_path, params: { subject_type: "Delivery", subject_id: 0, kind: "helpful" }
      assert_redirected_to app_root_path
    end
  end
end
