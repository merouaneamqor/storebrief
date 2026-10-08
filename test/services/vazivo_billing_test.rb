require "test_helper"

class VazivoBillingTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand(
      "billing-mix",
      features: { email_alerts: true, push_alerts: false, whatsapp_alerts: true },
      whatsapp_phone: "+212611111111"
    )
  end

  test "sums billed email and WhatsApp with separate unit prices" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Promo",
      body_fr: "Go",
      format: "task",
      status: "draft"
    )
    ActionMailer::Base.deliveries.clear
    brief.send_to!([ @brand.store.id ])

    assert NotificationLog.where(channel: "email", billed: true).exists?
    assert NotificationLog.where(channel: "whatsapp", billed: true).exists?

    snap = Vazivo::Billing.for(@brand.tenant)
    email = snap.channels.find { |c| c.channel == "email" }
    wa = snap.channels.find { |c| c.channel == "whatsapp" }

    assert_operator email.month_count, :>=, 1
    assert_operator wa.month_count, :>=, 1
    assert_equal email.month_count + wa.month_count, snap.month_count
    assert_equal(
      (email.month_count * email.unit_price) + (wa.month_count * wa.unit_price),
      snap.month_amount
    )
    assert_equal Vazivo::Billing.unit_price_for("email"), email.unit_price
    assert_equal Vazivo::Billing.unit_price_for("whatsapp"), wa.unit_price
  end
end
