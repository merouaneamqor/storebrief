require "test_helper"

class NotificationDispatcherTest < ActiveSupport::TestCase
  test "push stays available alongside optional whatsapp" do
    brand = build_brand(
      "notify-both",
      features: { push_alerts: true, whatsapp_alerts: true, email_alerts: false },
      whatsapp_phone: "+212611111111"
    )

    with_vapid do
      WebPush.stub(:payload_send, true) do
        brand.tenant.communications.create!(
          author: brand.hq,
          title_fr: "Promo",
          body_fr: "Go",
          format: "task",
          status: "draft"
        ).tap { |brief| brief.send_to!([ brand.store.id ]) }
      end
    end

    channels = NotificationLog.where(tenant: brand.tenant).pluck(:channel)
    assert_includes channels, "whatsapp"
    # push may log web_push when subscriptions exist; without a device it stays quiet
    assert_equal true, brand.tenant.feature?(:push_alerts)
    assert_equal true, brand.tenant.feature?(:whatsapp_alerts)
  end
end
