# frozen_string_literal: true

require "test_helper"

class HqWidgetsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("hq-widgets", features: { morocco_ops: true })
  end

  test "hq can open widget preferences and hide board sections" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Consigne widgets",
      body_fr: "Go",
      format: "task",
      status: "draft"
    )
    brief.send_to!([ @brand.store.id ])

    sign_in(@brand.hq)
    get app_root_path
    assert_response :success
    assert_select ".hq-status-strip"
    assert_select ".hq-compliance"
    assert_select ".hq-board"
    assert_select "a[href=?]", hq_widgets_path

    get hq_widgets_path
    assert_response :success
    assert_match I18n.t("morocco.hq.widgets.title", locale: :en), response.body
    Tenant::HQ_WIDGETS.each_key do |key|
      assert_select "#hq_widget_#{key}"
    end

    patch hq_widgets_path, params: {
      hq_widgets: {
        campaign: "1",
        exceptions: "1",
        podium: "1"
      }
    }
    assert_redirected_to hq_widgets_path
    follow_redirect!
    assert_match I18n.t("morocco.hq.widgets.saved", locale: :en), response.body

    tenant = @brand.tenant.reload
    assert tenant.hq_widget?(:campaign)
    assert tenant.hq_widget?(:exceptions)
    assert tenant.hq_widget?(:podium)
    assert_not tenant.hq_widget?(:store_status)
    assert_not tenant.hq_widget?(:compliance)
    assert_not tenant.hq_widget?(:monitoring)

    get app_root_path
    assert_response :success
    assert_select ".hq-status-strip", count: 0
    assert_select ".hq-compliance", count: 0
    assert_select ".hq-monitor", count: 0
    assert_select ".hq-board"
    assert_select ".hq-hero"
  end

  test "store users cannot open hq widgets settings" do
    sign_in(@brand.store_user)
    get hq_widgets_path
    assert_redirected_to app_root_path
  end

  test "hq widgets copy exists in fr en es ar" do
    %i[fr en es ar].each do |locale|
      assert I18n.t("morocco.hq.widgets.title", locale: locale).present?
      assert I18n.t("nav.hq_widgets", locale: locale).present?
      Tenant::HQ_WIDGETS.each_key do |key|
        assert I18n.t("morocco.hq.widgets.items.#{key}", locale: locale).present?, "#{locale} #{key}"
        assert I18n.t("morocco.hq.widgets.hints.#{key}", locale: locale).present?, "#{locale} hint #{key}"
      end
    end
  end
end
