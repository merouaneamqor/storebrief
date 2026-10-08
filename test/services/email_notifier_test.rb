require "test_helper"

class EmailNotifierTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "platform SMTP marks the email log as billed" do
    brand = build_brand("mail-platform", features: { email_alerts: true, whatsapp_alerts: false, push_alerts: false })
    brief = send_brief(brand)

    log = NotificationLog.find_by!(channel: "email", notifiable: brief)
    assert_equal "sent", log.status
    assert log.billed?
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "tenant SMTP sends without billing" do
    brand = build_brand("mail-tenant", features: { email_alerts: true, whatsapp_alerts: false, push_alerts: false })
    brand.tenant.create_mail_setting!(
      use_platform: false,
      from_email: "ops@atlas.test",
      from_name: "Atlas Ops",
      smtp_address: "smtp.example.test",
      smtp_port: 587,
      smtp_username: "ops",
      smtp_password: "secret"
    )

    brief = send_brief(brand)
    log = NotificationLog.find_by!(channel: "email", notifiable: brief)
    assert_equal "sent", log.status
    assert_not log.billed?
  end

  test "email alerts off skips mail" do
    brand = build_brand("mail-off", features: { email_alerts: false, whatsapp_alerts: false, push_alerts: false })
    send_brief(brand)
    assert_equal 0, NotificationLog.where(channel: "email").count
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  private

  def send_brief(brand)
    brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Vitrine",
      body_fr: "Merci de vérifier.",
      format: "task",
      status: "draft",
      source: "compose"
    ).tap { |brief| brief.send_to!([ brand.store.id ]) }
  end
end
