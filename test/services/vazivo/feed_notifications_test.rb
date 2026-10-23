require "test_helper"

class Vazivo::FeedNotificationsTest < ActiveSupport::TestCase
  test "engagement only sends push with feature and web push configured" do
    brand = build_brand("feed-push", features: { push_alerts: true })
    news = brand.tenant.communications.create!(author: brand.hq, title_fr: "News", body_fr: "News", format: "news", status: "draft")
    news.send_to!([ brand.store.id ])
    comment = FeedComment.create!(tenant: brand.tenant, user: brand.store_user, subject: news.deliveries.first, body: "Thanks")
    paid_before = NotificationLog.where(channel: %w[email whatsapp]).count
    calls = []
    PushNotifier.stub :deliver_to_user!, ->(**args) { calls << args } do
      WebPushConfig.stub :configured?, false do
        Vazivo::FeedNotifications.comment!(comment)
      end
      assert_empty calls
      WebPushConfig.stub :configured?, true do
        Vazivo::FeedNotifications.comment!(comment)
        assert_equal 1, calls.size
        assert_equal brand.hq, calls.first[:user]
        brand.tenant.update!(features: brand.tenant.features.merge("push_alerts" => false))
        Vazivo::FeedNotifications.comment!(comment)
        assert_equal 1, calls.size
      end
    end
    assert_equal paid_before, NotificationLog.where(channel: %w[email whatsapp]).count
  end
end
