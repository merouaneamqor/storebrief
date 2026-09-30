require "test_helper"

class PushNotifierTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(
      name: "Push Co",
      slug: "push-co",
      brand_name: "Push Co",
      **Tenant.default_palette
    )
    @region = @tenant.org_units.create!(name: "Casa", unit_type: "region")
    @store = @region.children.create!(name: "Store 1", unit_type: "store", tenant: @tenant)
    @hq = @tenant.users.create!(
      name: "HQ",
      email: "hq@push-co.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    @hq.memberships.create!(org_unit: @region, role: "hq")
    @store_user = @tenant.users.create!(
      name: "Store",
      email: "store@push-co.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    @store_user.memberships.create!(org_unit: @store, role: "store")
    @subscription = @store_user.push_subscriptions.create!(
      tenant: @tenant,
      endpoint: "https://push.example.test/sub/1",
      p256dh: "BNcRdreALRP-Bx7SccKNqE-h4SZr3kGkFLXB",
      auth: "tBHItJI5svbpez7KI4CCXg"
    )
  end

  test "skips when VAPID is not configured" do
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")

    checklist = @tenant.checklists.create!(
      author: @hq,
      title_fr: "Ouverture",
      title_ar: "فتح",
      status: "draft"
    )
    checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
    checklist.send_to!([ @store.id ])

    assert_equal 0, NotificationLog.where(channel: "web_push").count
  end

  test "sends web push when a checklist is sent" do
    ENV["VAPID_PUBLIC_KEY"] = "BPtestpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ENV["VAPID_PRIVATE_KEY"] = "testprivatekeyxxxxxxxxxxxxxxxxxxxxxxx"

    sent = []
    WebPush.stub(:payload_send, ->(**kwargs) { sent << kwargs; true }) do
      checklist = @tenant.checklists.create!(
        author: @hq,
        title_fr: "Ouverture",
        title_ar: "فتح",
        status: "draft"
      )
      checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
      checklist.send_to!([ @store.id ])
    end

    assert_equal 1, sent.size
    assert_equal @subscription.endpoint, sent.first[:endpoint]
    payload = JSON.parse(sent.first[:message])
    delivery = ChecklistDelivery.find_by!(checklist: Checklist.order(:id).last, org_unit: @store)
    assert_equal "/checklists/deliveries/#{delivery.id}", payload["url"]
    log = NotificationLog.find_by!(channel: "web_push", user: @store_user)
    assert_equal "sent", log.status
    assert_match(/New checklist/i, log.message)
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  test "removes expired subscriptions" do
    ENV["VAPID_PUBLIC_KEY"] = "BPtestpublickeyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    ENV["VAPID_PRIVATE_KEY"] = "testprivatekeyxxxxxxxxxxxxxxxxxxxxxxx"

    WebPush.stub(:payload_send, ->(**_kwargs) { raise WebPush::ExpiredSubscription.allocate }) do
      checklist = @tenant.checklists.create!(
        author: @hq,
        title_fr: "Promo",
        status: "draft"
      )
      checklist.checklist_items.create!(position: 0, title_fr: "PLV", requires_photo: false)
      checklist.send_to!([ @store.id ])
    end

    assert_not PushSubscription.exists?(@subscription.id)
    assert_equal "gone", NotificationLog.find_by!(channel: "web_push").status
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end
end
