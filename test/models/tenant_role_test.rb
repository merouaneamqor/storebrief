require "test_helper"

class TenantRoleTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("custom-roles")
    @other = build_brand("other-roles")
    @role = @brand.tenant.tenant_roles.create!(name: "Read only", base_role: "area", capabilities: %w[monitor reports])
    @area_user = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    @membership = @area_user.memberships.find_by!(role: "area")
    @membership.update!(tenant_role: @role)
  end

  test "defaults retain capabilities and custom roles can only reduce their base" do
    assert @brand.hq.allows?(:billing)
    assert @brand.store_user.allows?(:execute)
    assert @area_user.allows?(:monitor)
    assert_not @area_user.allows?(:visits)
    @role.capabilities = %w[monitor billing admin made_up]
    assert_not @role.valid?
  end

  test "capability grants stop at membership descendants and tenant boundary" do
    assert @area_user.allows?(:reports, org_unit: @brand.store)
    assert_not @area_user.allows?(:visits, org_unit: @brand.store)
    assert_not @area_user.allows?(:reports, org_unit: @other.store)
    sibling = @brand.tenant.org_units.create!(name: "Other region", unit_type: "region")
    assert_not @area_user.allows?(:reports, org_unit: sibling)
    assert_not @area_user.allows?(:reports, tenant_wide: true)
    assert @brand.hq.allows?(:billing, org_unit: sibling)
  end

  test "roles cannot be assigned across tenants or base workflows" do
    @membership.tenant_role = @other.tenant.tenant_roles.create!(name: "Other", base_role: "area", capabilities: [ "monitor" ])
    assert_not @membership.valid?
    @membership.tenant_role = @brand.tenant.tenant_roles.create!(name: "Store", base_role: "store", capabilities: [ "inbox" ])
    assert_not @membership.valid?
  end

  test "assigned role cannot change workflow or be silently deleted" do
    @role.base_role = "store"
    assert_not @role.valid?
    @role.reload
    assert_not @role.destroy
    assert @membership.reload.tenant_role
  end

  test "scoped custom HQ uses area scope and never becomes tenant administrator" do
    @brand.hq.memberships.first.update!(tenant_role: @brand.tenant.tenant_roles.create!(name: "Regional HQ", base_role: "hq", capabilities: [ "monitor" ]))
    @brand.tenant.org_units.create!(name: "Separate region", unit_type: "region")
    assert_not @brand.hq.hq?
    assert @brand.hq.area?
    assert_not @brand.hq.built_in_hq?
    assert @brand.hq.allows?(:monitor, org_unit: @brand.store)
    assert_not @brand.hq.allows?(:monitor, tenant_wide: true)
    membership = @brand.hq.memberships.first
    membership.tenant_role = nil
    assert_not membership.valid?
  end
  test "controller helper checks tenant and target scope rather than base role" do
    controller = ApplicationController.new
    Current.set(tenant: @brand.tenant) do
      controller.stub(:current_user, @area_user) do
        assert controller.send(:user_allows?, :reports, org_unit: @brand.store)
        assert_not controller.send(:user_allows?, :visits, org_unit: @brand.store)
        assert_not controller.send(:user_allows?, :reports, org_unit: @other.store)
      end
    end
  end

  test "different memberships do not lend their scope to another role capability" do
    region = @brand.tenant.org_units.create!(name: "Second", unit_type: "region")
    store = @brand.tenant.org_units.create!(name: "Second Store", unit_type: "store", parent: region)
    visits = @brand.tenant.tenant_roles.create!(name: "Visits", base_role: "area", capabilities: [ "visits" ])
    @area_user.memberships.create!(org_unit: region, role: "area", tenant_role: visits)
    assert_equal [ store.id ], @area_user.permitted_store_ids(:visits)
    assert_equal [ @brand.store.id ], @area_user.permitted_store_ids(:reports)
    assert_not @area_user.allows?(:visits, org_unit: @brand.store)
    assert @area_user.allows?(:visits, org_unit: store)
  end
end
