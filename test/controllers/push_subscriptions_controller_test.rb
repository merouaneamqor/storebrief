require "test_helper"

class PushSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @tenant = Tenant.create!(
      name: "Sub Co",
      slug: "sub-co",
      brand_name: "Sub Co",
      **Tenant.default_palette
    )
    region = @tenant.org_units.create!(name: "Rabat", unit_type: "region")
    store = region.children.create!(name: "Store 1", unit_type: "store", tenant: @tenant)
    @user = @tenant.users.create!(
      name: "Store",
      email: "store@sub-co.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    @user.memberships.create!(org_unit: store, role: "store")
  end

  test "vapid public key endpoint reports missing config" do
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")

    get push_vapid_public_key_path
    assert_response :service_unavailable
  end

  test "creates a push subscription for the signed-in user" do
    ENV["VAPID_PUBLIC_KEY"] = "BPtestpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ENV["VAPID_PRIVATE_KEY"] = "testprivatekeyxxxxxxxxxxxxxxxxxxxxxxx"

    post login_path, params: { tenant_slug: @tenant.slug, email: @user.email, password: "password" }

    assert_difference -> { @user.push_subscriptions.count }, 1 do
      post push_subscription_path, params: {
        endpoint: "https://push.example.test/abc",
        keys: { p256dh: "p256", auth: "authkey" }
      }, as: :json
    end

    assert_response :created
    sub = @user.push_subscriptions.last
    assert_equal "https://push.example.test/abc", sub.endpoint
    assert_equal @tenant.id, sub.tenant_id
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end
end
