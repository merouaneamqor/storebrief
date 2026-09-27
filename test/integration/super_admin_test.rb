require "test_helper"

class SuperAdminTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "platform admin sees every brand and can switch into one" do
    atlas = create_tenant("Atlas Switch", "atlas-switch")
    contoso = create_tenant("Contoso Switch", "contoso-switch")
    region = contoso.org_units.create!(name: "Casa", unit_type: "region")
    hq = contoso.users.create!(
      name: "Contoso HQ",
      email: "hq@contoso-switch.test",
      password: "password",
      password_confirmation: "password",
      locale: "fr"
    )
    hq.memberships.create!(org_unit: region, role: "hq")
    contoso.communications.create!(
      author: hq,
      title_fr: "Brief Contoso",
      body_fr: "Visible only inside Contoso.",
      format: "news",
      status: "sent"
    )

    admin = atlas.users.create!(
      name: "Platform Admin",
      email: "admin@switch.test",
      password: "password",
      password_confirmation: "password",
      locale: "fr",
      super_admin: true
    )

    post login_path, params: { email: admin.email, password: "password" }
    follow_redirect!

    assert_response :success
    assert_select "p.lede", text: /#{Regexp.escape(atlas.name)}/
    assert_select "select#tenant_id option[selected]", text: atlas.name

    get tenants_path
    assert_response :success
    assert_match atlas.name, response.body
    assert_match contoso.name, response.body
    assert_select "a.app-nav-link", text: I18n.t("nav.tenants", locale: :fr)

    post switch_tenants_path, params: { tenant_id: contoso.id, to: "dashboard" }
    follow_redirect!

    assert_response :success
    assert_select "p.lede", text: /#{Regexp.escape(contoso.name)}/
    assert_select "a", text: "Brief Contoso"
    assert_select "a", text: "Brief Atlas", count: 0

    get reports_path
    assert_response :success
    assert_match contoso.name, response.body
  end

  test "a store user cannot list or switch brands" do
    tenant = create_tenant("Atlas Locked", "atlas-locked")
    other = create_tenant("Other Locked", "other-locked")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store")
    user = tenant.users.create!(
      name: "Store",
      email: "store@atlas-locked.test",
      password: "password",
      password_confirmation: "password",
      locale: "fr"
    )
    user.memberships.create!(org_unit: store, role: "store")

    post login_path, params: { tenant_slug: tenant.slug, email: user.email, password: "password" }
    follow_redirect!

    get tenants_path
    assert_redirected_to app_root_path

    post switch_tenants_path, params: { tenant_id: other.id, to: "dashboard" }
    follow_redirect!
    assert_select "p.lede", text: /#{Regexp.escape(store.name)}/
    assert_select "select#tenant_id", count: 0
    assert_select "a", text: other.name, count: 0
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
end