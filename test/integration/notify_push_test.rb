require "test_helper"

class NotifyPushTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @tenant = Tenant.create!(
      name: "Notify Co",
      slug: "notify-co",
      brand_name: "Notify Co",
      **Tenant.default_palette
    )
    @region = @tenant.org_units.create!(name: "Casa", unit_type: "region")
    @store = @region.children.create!(name: "Store 1", unit_type: "store", tenant: @tenant)
    @hq = @tenant.users.create!(
      name: "HQ",
      email: "hq@notify-co.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    @hq.memberships.create!(org_unit: @region, role: "hq")
    @store_user = @tenant.users.create!(
      name: "Store",
      email: "store@notify-co.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    @store_user.memberships.create!(org_unit: @store, role: "store")
    @store_user.push_subscriptions.create!(
      tenant: @tenant,
      endpoint: "https://push.example.test/hq-trigger",
      p256dh: "p256",
      auth: "auth"
    )

    ENV["VAPID_PUBLIC_KEY"] = "BPtestpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ENV["VAPID_PRIVATE_KEY"] = "testprivatekeyxxxxxxxxxxxxxxxxxxxxxxx"
  end

  teardown do
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  test "hq can trigger push for pending checklist stores" do
    checklist = @tenant.checklists.create!(author: @hq, title_fr: "Ouverture", status: "draft")
    checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
    checklist.send_to!([ @store.id ])

    post login_path, params: { tenant_slug: @tenant.slug, email: @hq.email, password: "password" }

    WebPush.stub(:payload_send, true) do
      assert_difference -> { NotificationLog.where(channel: "web_push").count }, 1 do
        post notify_push_checklist_path(checklist)
      end
    end

    assert_redirected_to checklist_path(checklist)
    follow_redirect!
    assert_match(/Push sent/i, flash[:notice].to_s.presence || response.body)
  end

  test "hq can trigger push for pending brief stores" do
    brief = @tenant.communications.create!(
      author: @hq,
      title_fr: "Promo",
      body_fr: "Mettre la PLV",
      format: "task",
      status: "draft"
    )
    brief.send_to!([ @store.id ])

    post login_path, params: { tenant_slug: @tenant.slug, email: @hq.email, password: "password" }

    WebPush.stub(:payload_send, true) do
      post notify_push_communication_path(brief)
    end

    assert_redirected_to communication_path(brief)
  end

  test "super admin can trigger push while acting on a tenant" do
    super_admin = User.create!(
      name: "Platform",
      email: "admin@platform.test",
      password: "password",
      password_confirmation: "password",
      locale: "en",
      super_admin: true,
      tenant: @tenant
    )

    checklist = @tenant.checklists.create!(author: @hq, title_fr: "Promo", status: "draft")
    checklist.checklist_items.create!(position: 0, title_fr: "PLV", requires_photo: false)
    checklist.send_to!([ @store.id ])

    post login_path, params: { email: super_admin.email, password: "password" }
    follow_redirect!

    WebPush.stub(:payload_send, true) do
      post notify_push_checklist_path(checklist)
    end

    assert_response :redirect
  end
end
