require "test_helper"

class AppNavigationTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "headquarters menu is a checkbox the phone can open without Alpine" do
    tenant = Tenant.create!(
      name: "Atlas Nav",
      slug: "atlas-nav",
      brand_name: "Atlas",
      **Tenant.default_palette
    )
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    user = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-nav.test",
      password: "password",
      password_confirmation: "password",
      locale: "fr"
    )
    user.memberships.create!(org_unit: region, role: "hq")

    post login_path, params: { tenant_slug: tenant.slug, email: user.email, password: "password" }
    follow_redirect!

    assert_response :success
    assert_select "input#app-nav-toggle.app-nav-toggle"
    assert_select "label.app-menu-btn[for=app-nav-toggle]"
    assert_select "label.app-backdrop[for=app-nav-toggle]"
    assert_select "a.app-nav-link", text: I18n.t("nav.reports", locale: :fr)
    assert_no_match(/navOpen/, response.body)
    assert_operator response.body.index('type="module"'), :<, response.body.index("alpinejs")
  end
end
