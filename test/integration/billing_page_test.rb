require "test_helper"

class BillingPageTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand(
      "billing-hq",
      features: { email_alerts: true, push_alerts: false, whatsapp_alerts: true },
      whatsapp_phone: "+212622222222"
    )
  end

  test "hq sees billing usage and can switch to tenant smtp" do
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

    sign_in(@brand.hq)
    get billing_path
    assert_response :success
    assert_match I18n.t("billing.title", locale: :en), response.body
    assert_match I18n.t("billing.mode_platform", locale: :en), response.body
    assert_match I18n.t("billing.stat_month_whatsapp", locale: :en), response.body
    assert_match I18n.t("billing.recent_title", locale: :en), response.body
    assert_select "a.app-nav-link[href=?]", billing_path

    patch billing_path, params: {
      tenant_mail_setting: {
        use_platform: "0",
        from_email: "ops@billing-hq.test",
        from_name: "Billing HQ",
        smtp_address: "smtp.billing.test",
        smtp_port: 587,
        smtp_username: "ops",
        smtp_password: "secret",
        smtp_authentication: "plain",
        smtp_enable_starttls_auto: "1"
      }
    }
    assert_redirected_to billing_path
    follow_redirect!
    assert_match I18n.t("billing.mode_tenant", locale: :en), response.body
    setting = @brand.tenant.reload.mail_setting
    assert setting.configured_tenant_smtp?
  end

  test "store users cannot open billing" do
    sign_in(@brand.store_user)
    get billing_path
    assert_redirected_to app_root_path
  end
end
