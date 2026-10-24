# frozen_string_literal: true

require "test_helper"

class CndpPrivacyTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("cndp-privacy")
  end

  test "public privacy and cookies pages are available without login" do
    get legal_privacy_path
    assert_response :success
    assert_match I18n.t("privacy.page.title", locale: :fr), response.body

    get legal_cookies_path
    assert_response :success
    assert_match I18n.t("privacy.cookies.page_title", locale: :fr), response.body
  end

  test "demo request requires privacy consent" do
    post demo_requests_path, params: {
      demo_request: {
        name: "Test",
        company: "Retail Co",
        email: "demo@example.com",
        preferred_locale: "fr"
      }
    }
    assert_response :unprocessable_entity
    assert_match I18n.t("activerecord.errors.models.demo_request.attributes.base.privacy_consent_required", locale: :fr),
                 response.body
  end

  test "demo request stores consent timestamp" do
    post demo_requests_path, params: {
      demo_request: {
        name: "Test",
        company: "Retail Co",
        email: "demo@example.com",
        preferred_locale: "fr",
        privacy_consent: "1",
        marketing_contact_consent: "1"
      }
    }
    assert_redirected_to root_path(anchor: "demo")
    request = DemoRequest.order(:id).last
    assert request.privacy_consent_at.present?
    assert request.marketing_contact_consent?
  end

  test "new users must accept privacy notice before using the app" do
    user = @brand.store_user
    user.update!(privacy_notice_accepted_at: nil)

    post login_path, params: { tenant_slug: @brand.tenant.slug, email: user.email, password: "password" }
    follow_redirect!

    get app_root_path
    assert_redirected_to privacy_preferences_path

    patch privacy_preferences_path, params: { accept_privacy_notice: "1" }
    assert_redirected_to privacy_preferences_path
    assert user.reload.privacy_notice_accepted_at.present?

    get app_root_path
    assert_response :success
  end

  test "whatsapp alerts require user consent" do
    brand = build_brand(
      "cndp-wa",
      features: { whatsapp_alerts: true },
      whatsapp_phone: "+212600000099",
      whatsapp_alerts_consent_at: nil
    )
    checklist = brand.tenant.checklists.create!(author: brand.hq, title_fr: "Test", status: "draft")
    checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
    checklist.send_to!([ brand.store.id ])

    WhatsappNotifier.notify_checklist!(checklist)
    assert_equal 0, NotificationLog.where(channel: "whatsapp").count

    brand.store_user.update!(whatsapp_alerts_consent_at: Time.current)
    WhatsappNotifier.notify_checklist!(checklist)
    assert_equal 1, NotificationLog.where(channel: "whatsapp").count
  end
end
