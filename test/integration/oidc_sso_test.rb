require "test_helper"

class OidcSsoTest < ActionDispatch::IntegrationTest
  include OidcHelpers

  setup do
    Rails.cache.clear
    host! "localhost"
    @brand = build_brand("oidc-sso")
    @setting = configure_oidc(@brand.tenant)
  end

  test "authorization uses PKCE nonce and state; verified JIT creates a scoped account and session" do
    flow = start_oidc(@setting)
    assert_equal "code", flow["response_type"]
    assert_equal "S256", flow["code_challenge_method"]
    assert_equal "openid email profile", flow["scope"]
    assert_equal @setting.client_id, flow["client_id"]
    assert_not_equal flow["state"], flow["nonce"]
    attempt = OidcLoginAttempt.last
    assert_not_equal flow["state"], attempt.state_digest
    assert_not_includes attempt.code_verifier_ciphertext, attempt.code_verifier
    assert_difference "User.count", 1 do
      complete_oidc(@setting, flow)
    end
    assert_redirected_to app_root_path
    user = User.find(session[:user_id])
    assert_equal "employee@oidc-sso.test", user.email
    assert_not user.authenticate("password")
    membership = user.memberships.sole
    assert_equal @brand.store.id, membership.org_unit_id
    assert_equal "store", membership.role
    assert_equal user.oidc_identity.id, membership.oidc_identity_id
    assert attempt.reload.consumed_at
  end

  test "forged algorithm signature issuer audience expiry nonce azp and email claims fail closed" do
    invalid = [
      { iss: "https://evil.example.com" }, { aud: "another-client" }, { exp: 1.minute.ago.to_i },
      { nonce: "wrong-nonce" }, { email_verified: false }, { email_verified: "true" },
      { aud: [ @setting.client_id, "other" ], azp: "other" }, { iat: 1.hour.from_now.to_i },
      { sub: "" }, { email: "invalid" }
    ]
    invalid.each do |claims|
      flow = start_oidc(@setting)
      assert_no_difference [ "User.count", "OidcIdentity.count" ] do
        complete_oidc(@setting, flow, claims: claims)
      end
      assert_redirected_to login_path(tenant_slug: @brand.tenant.slug)
      assert_nil session[:user_id]
    end
    %w[HS256 none].each do |algorithm|
      flow = start_oidc(@setting)
      payload = signed_oidc_claims(@setting, nonce: flow["nonce"])
      complete_oidc(@setting, flow, token: oidc_token(payload, key: (algorithm == "none" ? nil : "forged"), algorithm: algorithm))
      assert_nil session[:user_id]
    end
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, token: oidc_token(signed_oidc_claims(@setting, nonce: flow["nonce"]), key: OpenSSL::PKey::RSA.generate(2048)))
    assert_nil session[:user_id]
  end

  test "attempts are browser bound single use and expire without contacting the provider" do
    flow = start_oidc(@setting)
    stranger = open_session
    stranger.host! "localhost"
    stranger.get oidc_callback_path(@brand.tenant.slug), params: { state: flow["state"], code: "stolen" }
    assert_nil stranger.session[:user_id]
    assert_nil OidcLoginAttempt.last.consumed_at
    complete_oidc(@setting, flow)
    user_id = session[:user_id]
    assert user_id
    Oidc::SafeHttp.stub(:json, ->(*) { flunk "replay contacted provider" }) do
      get oidc_callback_path(@brand.tenant.slug), params: { state: flow["state"], code: "replay" }
    end
    assert_equal user_id, session[:user_id]
    flow = start_oidc(@setting)
    OidcLoginAttempt.last.update!(expires_at: 1.second.ago)
    Oidc::SafeHttp.stub(:json, ->(*) { flunk "expired attempt contacted provider" }) do
      get oidc_callback_path(@brand.tenant.slug), params: { state: flow["state"], code: "expired" }
    end
    assert_redirected_to login_path(tenant_slug: @brand.tenant.slug)
  end

  test "tenant and provider configuration bind attempts and disabled callback cannot authenticate" do
    flow = start_oidc(@setting)
    other = build_brand("oidc-other")
    configure_oidc(other.tenant)
    get oidc_callback_path(other.tenant.slug), params: { state: flow["state"], code: "wrong-tenant" }
    assert_nil session[:user_id]
    assert_nil OidcLoginAttempt.last.consumed_at
    @setting.update!(client_id: "changed-client")
    get oidc_callback_path(@brand.tenant.slug), params: { state: flow["state"], code: "changed" }
    assert_nil session[:user_id]
    @setting.update!(enabled: false)
    assert_no_difference "OidcLoginAttempt.count" do
      get oidc_login_path(@brand.tenant.slug)
    end
    get oidc_callback_path(@brand.tenant.slug), params: { state: flow["state"], code: "disabled" }
    assert_nil session[:user_id]
    @setting.update!(enabled: true)
    @brand.tenant.update!(feature_oidc_sso: false)
    get oidc_login_path(@brand.tenant.slug)
    assert_redirected_to login_path(tenant_slug: @brand.tenant.slug)
  end

  test "JIT is opt in and verified existing store accounts keep unrelated manual memberships" do
    @setting.update!(jit_enabled: false)
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow)
    assert_nil session[:user_id]
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, claims: { email: @brand.store_user.email })
    assert_equal @brand.store_user.id, session[:user_id]
    assert_nil @brand.store_user.memberships.sole.oidc_identity_id
    assert @brand.store_user.reload.oidc_identity
  end

  test "role synchronization revokes managed grants on group loss while preserving manual memberships" do
    @setting.update!(role_mappings: @setting.role_mappings + [ { "claim" => "site", "value" => "region-team", "role" => "area", "org_unit_id" => @brand.region.id } ])
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow)
    user = User.find(session[:user_id])
    old = user.memberships.sole.id
    manual_store = @brand.tenant.org_units.create!(name: "Manual store", unit_type: "store", parent: @brand.region)
    manual = user.memberships.create!(org_unit: manual_store, role: "store")
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, claims: { groups: [], site: "region-team" })
    assert_not Membership.exists?(old)
    assert_equal "area", user.oidc_identity.memberships.sole.role
    assert Membership.exists?(manual.id)
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, claims: { groups: [] })
    assert_nil session[:user_id]
    assert_empty user.oidc_identity.memberships
    assert Membership.exists?(manual.id)
  end

  test "HQ email cannot be auto linked and only an explicit issuer subject link preserves admin access" do
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, claims: { email: @brand.hq.email })
    assert_nil session[:user_id]
    assert_nil @brand.hq.reload.oidc_identity
    identity = @brand.tenant.oidc_identities.create!(user: @brand.hq, issuer: @setting.issuer, subject: "admin-subject", admin_linked: true)
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, claims: { sub: identity.subject, email: @brand.hq.email, groups: [] })
    assert_equal @brand.hq.id, session[:user_id]
    assert @brand.hq.reload.built_in_hq?
    assert_nil @brand.hq.memberships.sole.oidc_identity_id
  end

  test "SSO enforcement blocks passwords and localized login offers OIDC alongside SAML" do
    @setting.update!(sso_enforced: true)
    post login_path, params: { tenant_slug: @brand.tenant.slug, email: @brand.hq.email, password: "password" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
    %w[fr ar en es].each do |locale|
      get login_path, params: { tenant_slug: @brand.tenant.slug, locale: locale }
      assert_response :success
      assert_select "a[href=?]", oidc_login_path(@brand.tenant.slug), text: I18n.t("oidc.sign_in", locale: locale)
      assert_select "input[name=password]", count: 0
    end
  end
  test "untrusted key headers unknown keys and wrong key metadata never authenticate" do
    [ { kid: nil }, { kid: "unknown" }, { jku: "https://evil.example.com/keys" }, { jwk: { kty: "RSA" } } ].each do |headers|
      flow = start_oidc(@setting)
      token = oidc_token(signed_oidc_claims(@setting, nonce: flow["nonce"]), headers: headers)
      complete_oidc(@setting, flow, token: token)
      assert_nil session[:user_id]
    end
    flow = start_oidc(@setting)
    jwk = JSON.parse(JSON.generate(JWK.export))
    complete_oidc(@setting, flow, jwks: { "keys" => [ jwk, jwk ] })
    assert_nil session[:user_id]
    flow = start_oidc(@setting)
    complete_oidc(@setting, flow, jwks: { "keys" => [ jwk.merge("use" => "enc") ] })
    assert_nil session[:user_id]
  end

  test "a tenant account cannot borrow the platform admin email password exemption" do
    @setting.update!(sso_enforced: true)
    other = build_brand("oidc-admin-email")
    other.hq.update!(super_admin: true)
    clone = create_user(@brand.tenant, org_unit: @brand.store, role: :store, email: other.hq.email)
    post login_path, params: { tenant_slug: @brand.tenant.slug, email: clone.email, password: "password" }
    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end
  test "malformed provider keys fail without exposing a server error" do
    [ { "n" => nil }, { "n" => "!bad" }, { "e" => {} } ].each do |attributes|
      flow = start_oidc(@setting)
      jwk = JSON.parse(JSON.generate(JWK.export)).merge(attributes)
      complete_oidc(@setting, flow, jwks: { "keys" => [ jwk ] })
      assert_redirected_to login_path(tenant_slug: @brand.tenant.slug)
      assert_nil session[:user_id]
    end
  end
end
