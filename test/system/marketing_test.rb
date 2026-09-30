require "application_system_test_case"

class MarketingSystemTest < ApplicationSystemTestCase
  test "visitor books a demo from the landing page" do
    visit root_path

    within "form[action='#{demo_requests_path}']" do
      fill_in "demo_request_name", with: "Salma Idrissi"
      fill_in "demo_request_company", with: "Marjane Test"
      fill_in "demo_request_email", with: "salma@example.test"
      fill_in "demo_request_store_count", with: "40"
      click_button I18n.t("landing.demo.submit", locale: :fr)
    end

    assert_text I18n.t("landing.demo.success", locale: :fr)
    request = DemoRequest.last
    assert_equal "Marjane Test", request.company
    assert_equal 40, request.store_count
  end

  test "switching to Arabic flips the page to right-to-left" do
    visit root_path
    assert_selector "html[dir=ltr]", visible: false

    first("select.locale-select").select I18n.t("locales.ar", locale: :fr)
    assert_selector "html[dir=rtl][lang=ar]", visible: false

    first("select.locale-select").select I18n.t("locales.fr", locale: :ar)
    assert_selector "html[dir=ltr][lang=fr]", visible: false
  end

  test "an Arabic store user gets the app in right-to-left" do
    brand = build_brand("atlas-rtl", store_locale: "ar")

    log_in_as(brand.store_user)
    assert_selector "html[dir=rtl][lang=ar]", visible: false
    assert_selector "a.app-nav-link", text: I18n.t("nav.inbox", locale: :ar)
  end
end
