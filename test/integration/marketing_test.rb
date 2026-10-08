require "test_helper"

class MarketingTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "homepage shows one morning and does not sell a roadmap" do
    get root_path

    assert_response :success
    assert_select "h1", I18n.t("landing.hero.title", locale: :fr)
    assert_select "#problems"
    assert_select "#how"
    assert_select "#demo form"
    assert_match I18n.t("landing.hero.scene_status", locale: :fr), response.body
    assert_match I18n.t("landing.faq.a1", locale: :fr), response.body
    assert_match I18n.t("landing.demo.reassure", locale: :fr), response.body
    assert_no_match(/WhatsApp/i, response.body)
    assert_no_match(/Électronique et électroménager/, response.body)
    assert_no_match(/meilleurs prospects/, response.body)
  end

  test "arabic renders right to left" do
    patch locale_path, params: { locale: "ar" }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_select "html[lang=ar][dir=rtl]"
    assert_match I18n.t("landing.hero.title", locale: :ar), response.body
    assert_match I18n.t("landing.hero.store_c", locale: :ar), response.body
  end

  test "who it's for keeps the format list off the sales-jargon headings" do
    get resources_path

    assert_response :success
    assert_match "Électronique et électroménager", response.body
    assert_match I18n.t("landing.prospects.strongest", locale: :fr), response.body
    assert_no_match(/meilleurs prospects/, response.body)
  end

  test "demo request accepts a phone number without an email" do
    assert_difference -> { DemoRequest.count }, 1 do
      post demo_requests_path, params: {
        demo_request: {
          name: "Amina Benali",
          company: "Atlas Retail",
          phone: "0612345678",
          preferred_locale: "fr",
          store_count: 12
        }
      }
    end

    assert_redirected_to root_path(anchor: "demo")
    follow_redirect!
    assert_match I18n.t("landing.demo.success", locale: :fr), response.body
  end

  test "demo request without a contact stays on the form" do
    assert_no_difference -> { DemoRequest.count } do
      post demo_requests_path, params: {
        demo_request: {
          name: "Amina Benali",
          company: "Atlas Retail",
          preferred_locale: "fr"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_match "Amina Benali", response.body
    assert_select "#demo .m-form__error"
  end
end
