require "test_helper"

class CriticalBroadcastNotificationsTest < ActiveSupport::TestCase
  test "critical broadcasts dispatch push and only explicitly selected billed channels" do
    brand = build_brand("broadcast-channels", features: { push_alerts: true, email_alerts: true, whatsapp_alerts: true })
    broadcast = build_broadcast(brand)
    calls = []
    PushNotifier.stub(:notify_communication!, ->(item) { calls << [ :push, item.id ] }) do
      EmailNotifier.stub(:notify_communication!, ->(item) { calls << [ :email, item.id ] }) do
        WhatsappNotifier.stub(:notify_communication!, ->(item) { calls << [ :whatsapp, item.id ] }) do
          NotificationDispatcher.notify_communication!(broadcast)
          assert_equal [ [ :push, broadcast.id ] ], calls
          broadcast.update!(broadcast_email: true, broadcast_whatsapp: true)
          calls.clear
          NotificationDispatcher.notify_communication!(broadcast)
          assert_equal [ [ :push, broadcast.id ], [ :email, broadcast.id ], [ :whatsapp, broadcast.id ] ], calls
        end
      end
    end
  end

  test "critical optional channels cannot override disabled tenant channels" do
    brand = build_brand("broadcast-disabled", features: { push_alerts: false, email_alerts: false, whatsapp_alerts: false })
    broadcast = build_broadcast(brand, broadcast_email: true, broadcast_whatsapp: true)
    calls = []
    PushNotifier.stub(:notify_communication!, ->(*) { calls << :push }) do
      EmailNotifier.stub(:notify_communication!, ->(*) { calls << :email }) do
        WhatsappNotifier.stub(:notify_communication!, ->(*) { calls << :whatsapp }) do
          NotificationDispatcher.notify_communication!(broadcast)
        end
      end
    end
    assert_empty calls
  end

  test "push stays free while opted in platform email and WhatsApp are billed" do
    brand = build_brand("broadcast-billing", features: { email_alerts: true, whatsapp_alerts: true }, whatsapp_phone: "+212611111112")
    brand.store_user.push_subscriptions.create!(tenant: brand.tenant, endpoint: "https://push.example.test/broadcast", p256dh: "test-key", auth: "test-auth")
    broadcast = build_broadcast(brand, broadcast_email: true, broadcast_whatsapp: true)
    PlatformMail.stub(:configured?, true) do
      with_vapid do
        WebPush.stub(:payload_send, true) { broadcast.send_to!([ brand.store.id ]) }
      end
    end
    logs = NotificationLog.where(notifiable: broadcast)
    assert_equal false, logs.find_by!(channel: "web_push").billed
    assert_equal true, logs.find_by!(channel: "email").billed
    assert_equal true, logs.find_by!(channel: "whatsapp").billed
    assert_match(/Critical broadcast/, logs.find_by!(channel: "whatsapp").message)
  end

  test "broadcast settings are removed for tasks or when Morocco operations are off" do
    brand = build_brand("broadcast-normalize")
    task = build_broadcast(brand, format: "task", broadcast_email: true, broadcast_whatsapp: true)
    assert_not task.critical_broadcast?
    assert_not task.requires_acknowledgement?
    assert_not task.broadcast_email?
    assert_not task.broadcast_whatsapp?
    brand.tenant.update!(features: brand.tenant.features.merge("morocco_ops" => false))
    announcement = build_broadcast(brand)
    assert_not announcement.critical_broadcast?
    assert_not announcement.requires_acknowledgement?
    assert_equal "routine", announcement.priority
  end

  private

  def build_broadcast(brand, **attrs)
    brand.tenant.communications.create!(
      author: brand.hq, title_fr: "Consigne sécurité", body_fr: "Vérifiez les sorties.",
      format: "announcement", critical_broadcast: true, requires_acknowledgement: true, **attrs
    )
  end
end
