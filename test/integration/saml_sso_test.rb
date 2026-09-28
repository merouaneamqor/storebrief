# frozen_string_literal: true

require "test_helper"

class SamlSsoTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "metadata is available for a tenant" do
    tenant = create_tenant("SAML Meta", "saml-meta")

    get saml_metadata_path(tenant.slug)

    assert_response :success
    assert_includes response.body, "EntityDescriptor"
    assert_includes response.body, "/saml/saml-meta/acs"
  end

  test "sso redirects to login when not configured" do
    tenant = create_tenant("SAML Off", "saml-off")

    get saml_sso_path(tenant.slug)

    assert_redirected_to login_path(tenant_slug: tenant.slug)
  end

  test "sso redirects to IdP when enabled" do
    tenant = create_tenant("SAML On", "saml-on")
    tenant.update!(feature_saml_sso: true)
    tenant.create_saml_setting!(
      enabled: true,
      idp_entity_id: "https://idp.example.com/saml-on",
      idp_sso_target_url: "https://idp.example.com/saml-on/sso",
      idp_cert: sample_cert,
      email_attribute: "email"
    )

    get saml_sso_path(tenant.slug)

    assert_response :redirect
    assert_match %r{\Ahttps://idp\.example\.com/saml-on/sso}, response.redirect_url
  end

  test "password login blocked when sso enforced" do
    tenant = create_tenant("SAML Enforce", "saml-enforce")
    tenant.update!(feature_saml_sso: true)
    tenant.create_saml_setting!(
      enabled: true,
      sso_enforced: true,
      idp_entity_id: "https://idp.example.com/saml-enforce",
      idp_sso_target_url: "https://idp.example.com/saml-enforce/sso",
      idp_cert: sample_cert
    )
    user = tenant.users.create!(
      name: "HQ",
      email: "hq@saml-enforce.test",
      password: "password",
      password_confirmation: "password",
      locale: "fr"
    )

    post login_path, params: {
      tenant_slug: tenant.slug,
      email: user.email,
      password: "password"
    }

    assert_response :unprocessable_entity
    assert_nil session[:user_id]
  end

  test "login page shows sso only on tenant host when configured" do
    tenant = create_tenant("SAML Login UI", "saml-ui")
    tenant.update!(feature_saml_sso: true)
    tenant.create_saml_setting!(
      enabled: true,
      idp_entity_id: "https://idp.example.com/saml-ui",
      idp_sso_target_url: "https://idp.example.com/saml-ui/sso",
      idp_cert: sample_cert
    )

    host! "localhost"
    get login_path, params: { tenant_slug: tenant.slug }
    assert_response :success
    assert_select "a.m-btn", text: I18n.t("auth.sso_sign_in", locale: :fr), count: 0

    host! "#{tenant.slug}.localhost"
    get login_path
    assert_response :success
    assert_select "a.m-btn", text: I18n.t("auth.sso_sign_in", locale: :fr)
    assert_select "p.m-login__divider", text: /#{Regexp.escape(I18n.t("auth.sso_or_password", locale: :fr))}/
  end

  test "login page hides sso when feature flag is off" do
    tenant = create_tenant("SAML Flag Off", "saml-flag-off")
    tenant.update!(feature_saml_sso: false)
    tenant.create_saml_setting!(
      enabled: true,
      idp_entity_id: "https://idp.example.com/saml-flag-off",
      idp_sso_target_url: "https://idp.example.com/saml-flag-off/sso",
      idp_cert: sample_cert
    )

    host! "#{tenant.slug}.localhost"
    get login_path

    assert_response :success
    assert_select "a.m-btn", text: I18n.t("auth.sso_sign_in", locale: :fr), count: 0
  end

  test "login page hides sso when not configured on tenant host" do
    tenant = create_tenant("SAML None", "saml-none")

    host! "#{tenant.slug}.localhost"
    get login_path

    assert_response :success
    assert_select "a.m-btn", text: I18n.t("auth.sso_sign_in", locale: :fr), count: 0
    assert_select "p.m-login__divider", count: 0
  end

  private

  def create_tenant(name, slug)
    Tenant.create!(
      name: name,
      slug: slug,
      brand_name: name.split.first,
      **Tenant.default_palette
    )
  end

  def sample_cert
    # Minimal PEM shape accepted by TenantSamlSetting validation (not used for crypto in these tests)
    <<~CERT
      -----BEGIN CERTIFICATE-----
      MIIBkTCB+wIJAJexample00000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      -----END CERTIFICATE-----
    CERT
  end
end
