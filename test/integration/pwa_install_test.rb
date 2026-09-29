require "test_helper"

class PwaInstallTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "manifest is served as an installable web app manifest" do
    get pwa_manifest_path
    assert_response :success
    assert_includes response.media_type, "json"

    body = JSON.parse(response.body)
    assert_equal "StoreBrief", body["name"]
    assert_equal "standalone", body["display"]
    assert_equal "/app", body["start_url"]
    assert body["icons"].any? { |icon| icon["sizes"] == "192x192" }
    assert body["icons"].any? { |icon| icon["sizes"] == "512x512" }
  end

  test "service worker is served with push handlers" do
    get pwa_service_worker_path
    assert_response :success
    assert_match(/addEventListener\(["']fetch["']/, response.body)
    assert_match(/addEventListener\(["']push["']/, response.body)
    assert_match(/addEventListener\(["']notificationclick["']/, response.body)
  end

  test "app layout exposes install prompt and PWA meta" do
    tenant = Tenant.create!(
      name: "PWA Co",
      slug: "pwa-co",
      brand_name: "PWA Co",
      **Tenant.default_palette
    )
    region = tenant.org_units.create!(name: "Rabat", unit_type: "region")
    user = tenant.users.create!(
      name: "Store",
      email: "store@pwa-co.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    store = region.children.create!(name: "Store 1", unit_type: "store", tenant: tenant)
    user.memberships.create!(org_unit: store, role: "store")

    post login_path, params: { tenant_slug: tenant.slug, email: user.email, password: "password" }
    follow_redirect!

    assert_response :success
    assert_select 'link[rel=manifest][href=?]', pwa_manifest_path
    assert_select 'meta[name="theme-color"][content="#0c6b58"]'
    assert_select 'link[rel=apple-touch-icon][href="/icon.png"]'
    assert_select ".pwa-install"
    assert_select "#pwa-install-title", text: I18n.t("pwa.title", locale: :en)
    assert_match(/pwaInstall/, response.body)
    assert_match(/pwaPush/, response.body)
  end

  test "app layout exposes push meta when VAPID is configured" do
    ENV["VAPID_PUBLIC_KEY"] = "BPtestpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ENV["VAPID_PRIVATE_KEY"] = "testprivatekeyxxxxxxxxxxxxxxxxxxxxxxx"

    tenant = Tenant.create!(
      name: "Push Meta",
      slug: "push-meta",
      brand_name: "Push Meta",
      **Tenant.default_palette
    )
    region = tenant.org_units.create!(name: "Fes", unit_type: "region")
    user = tenant.users.create!(
      name: "Store",
      email: "store@push-meta.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    store = region.children.create!(name: "Store 1", unit_type: "store", tenant: tenant)
    user.memberships.create!(org_unit: store, role: "store")

    post login_path, params: { tenant_slug: tenant.slug, email: user.email, password: "password" }
    follow_redirect!

    assert_response :success
    assert_select 'meta[name="push-configured"][content="1"]'
    assert_select 'meta[name="vapid-public-key"]'
    assert_select ".pwa-push"
    assert_select "#pwa-push-title", text: I18n.t("pwa.push.title", locale: :en)
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end
end
