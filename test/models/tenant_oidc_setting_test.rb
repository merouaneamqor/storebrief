require "test_helper"

class TenantOidcSettingTest < ActiveSupport::TestCase
  include OidcHelpers

  setup do
    @brand = build_brand("oidc-config")
    @setting = configure_oidc(@brand.tenant)
  end

  test "client secret uses authenticated encryption and blank edits preserve it" do
    assert_equal "private-client-secret", @setting.reload.client_secret
    assert_not_includes @setting.client_secret_ciphertext, "private-client-secret"
    @setting.update!(client_secret: "")
    assert_equal "private-client-secret", @setting.reload.client_secret
    encrypted = @setting.client_secret_ciphertext
    assert_raises(Oidc::Error) { Oidc::Secrets.decrypt(encrypted, purpose: "oidc pkce") }
  end

  test "mapping cannot cross tenants grant built-in HQ or accept malformed claims" do
    other = build_brand("oidc-foreign-config")
    [
      { "claim" => "groups", "value" => "admins", "role" => "hq", "org_unit_id" => @brand.region.id },
      { "claim" => "groups", "value" => "stores", "role" => "store", "org_unit_id" => other.store.id },
      { "claim" => "groups", "value" => "stores", "tenant_role_id" => 999999, "org_unit_id" => @brand.store.id },
      { "claim" => "nested.bad", "value" => "stores", "role" => "store", "org_unit_id" => @brand.store.id }
    ].each do |mapping|
      @setting.role_mappings = [ mapping ]
      assert_not @setting.valid?
    end
    @setting.role_mappings_json = "not JSON"
    assert_not @setting.valid?
  end

  test "custom role mapping preserves its scoped capability subset" do
    role = @brand.tenant.tenant_roles.create!(name: "Inbox only", base_role: "store", capabilities: [ "inbox" ])
    @setting.update!(role_mappings: [ { "claim" => "groups", "value" => "store-team", "tenant_role_id" => role.id, "org_unit_id" => @brand.store.id } ])
    claims = signed_oidc_claims(@setting, nonce: "nonce")
    user = Oidc::Provisioner.new(@setting, claims).call
    assert user.allows?(:inbox, org_unit: @brand.store)
    assert_not user.allows?(:execute)
    assert_equal role.id, user.memberships.sole.tenant_role_id
  end

  test "repeated subjects cannot relink an existing bound account" do
    claims = signed_oidc_claims(@setting, nonce: "nonce")
    user = Oidc::Provisioner.new(@setting, claims).call
    assert_raises(Oidc::Error) { Oidc::Provisioner.new(@setting, claims.merge("sub" => "other-person")).call }
    assert_equal "employee-1", user.oidc_identity.subject
  end
  test "ambiguous mappings revoke old SSO grants and refuse the next login" do
    claims = signed_oidc_claims(@setting, nonce: "nonce")
    user = Oidc::Provisioner.new(@setting, claims).call
    @setting.update!(role_mappings: @setting.role_mappings + [ { "claim" => "groups", "value" => "other-team", "role" => "area", "org_unit_id" => @brand.store.id } ])
    assert_raises(Oidc::Error) do
      Oidc::Provisioner.new(@setting, claims.merge("groups" => %w[store-team other-team])).call
    end
    assert_empty user.reload.memberships
  end

  test "conflicting manual membership is never overwritten by a signed claim" do
    @brand.store_user.memberships.sole.update!(role: "area")
    claims = signed_oidc_claims(@setting, nonce: "nonce", email: @brand.store_user.email)
    assert_raises(Oidc::Error) { Oidc::Provisioner.new(@setting, claims).call }
    membership = @brand.store_user.memberships.sole
    assert_equal "area", membership.role
    assert_nil membership.oidc_identity_id
  end
  test "oversized provider fields and malformed mapping identifiers produce validation errors" do
    @setting.issuer = "https://idp.example.com/" + "x" * 256
    assert_not @setting.valid?
    @setting.reload
    @setting.enabled = false
    @setting.client_id = "x" * 256
    assert_not @setting.valid?
    @setting.reload
    @setting.role_mappings = [ { "claim" => "groups", "value" => "store-team", "role" => "store", "org_unit_id" => [ @brand.store.id ] } ]
    assert_not @setting.valid?
  end
end
