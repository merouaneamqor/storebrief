require "test_helper"

class OidcSettingsTest < ActionDispatch::IntegrationTest
  include OidcHelpers

  setup do
    host! "localhost"
    @brand = build_brand("oidc-settings")
    @setting = configure_oidc(@brand.tenant)
  end

  test "HQ config is localized and never echoes the stored or submitted secret" do
    sign_in(@brand.hq)
    %w[fr ar en es].each do |locale|
      get oidc_settings_path, params: { locale: locale }
      assert_response :success
      assert_select "h1", text: I18n.t("oidc.title", locale: locale)
      assert_select "input[name='tenant_oidc_setting[client_secret]'][value]", count: 0
      assert_not_includes response.body, "private-client-secret"
    end
    patch oidc_settings_path, params: { tenant_oidc_setting: { client_secret: "replacement-private-secret", role_mappings_json: "invalid-json" } }
    assert_response :unprocessable_entity
    assert_not_includes response.body, "replacement-private-secret"
    assert_equal "private-client-secret", @setting.reload.client_secret
    patch oidc_settings_path, params: { tenant_oidc_setting: { client_secret: "replacement-private-secret" } }
    assert_redirected_to oidc_settings_path
    assert_equal "replacement-private-secret", @setting.reload.client_secret
  end

  test "area store and custom HQ roles cannot configure SSO or link identities" do
    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    custom = @brand.tenant.tenant_roles.create!(name: "HQ monitor", base_role: "hq", capabilities: [ "monitor" ])
    custom_user = create_user(@brand.tenant, org_unit: @brand.store, role: :hq, email: "custom@oidc-settings.test")
    custom_user.memberships.sole.update!(tenant_role: custom)
    [ area, @brand.store_user, custom_user ].each do |user|
      sign_in(user)
      get oidc_settings_path
      assert_redirected_to app_root_path
      patch oidc_settings_path, params: { tenant_oidc_setting: { sso_enforced: true } }
      assert_redirected_to app_root_path
      assert_not @setting.reload.sso_enforced?
      assert_no_difference "OidcIdentity.count" do
        post link_oidc_settings_path, params: { user_id: @brand.hq.id, subject: "admin" }
      end
    end
  end

  test "identity linking and unlinking stay tenant scoped and preserve manual memberships" do
    other = build_brand("oidc-link-foreign")
    sign_in(@brand.hq)
    post link_oidc_settings_path, params: { user_id: other.hq.id, subject: "foreign" }
    assert_response :not_found
    assert_difference "OidcIdentity.count", 1 do
      post link_oidc_settings_path, params: { user_id: @brand.store_user.id, subject: "store-subject" }
    end
    identity = @brand.store_user.reload.oidc_identity
    assert identity.admin_linked?
    manual_id = @brand.store_user.memberships.sole.id
    @brand.store_user.memberships.create!(org_unit: @brand.region, role: "area", oidc_identity: identity)
    delete unlink_oidc_settings_path, params: { identity_id: identity.id }
    assert Membership.exists?(manual_id)
    assert_not OidcIdentity.exists?(identity.id)
    assert_equal 1, @brand.store_user.memberships.count
  end
end
