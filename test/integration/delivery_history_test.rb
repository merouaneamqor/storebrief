require "test_helper"

class DeliveryHistoryTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("history-ui", features: { morocco_ops: true })
    @tenant = @brand.tenant
  end

  test "status awareness verdict and proof changes are logged tenant-scoped" do
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Vitrine", body_fr: "Corps", format: "task",
      status: "draft", requires_proof: true
    )
    brief.send_to!([ @brand.store.id ])
    delivery = brief.deliveries.first

    sign_in @brand.store_user
    %w[received read understood in_progress].each do |step|
      post advance_inbox_path(delivery), params: { step: step }
      assert_response :redirect
    end
    assert delivery.reload.delivery_events.where(kind: "awareness").exists?

    photo = fixture_file_upload("window.jpg", "image/jpeg")
    post advance_inbox_path(delivery), params: { step: "done", photo_before: photo, photo_after: photo }
    delivery.reload
    assert delivery.delivery_events.where(kind: "proof").exists?
    assert delivery.delivery_events.where(kind: "status").exists?
    assert delivery.delivery_events.all? { |event| event.tenant_id == @tenant.id }

    delete logout_path
    sign_in @brand.hq
    post delivery_verdict_path(delivery), params: { verdict: "conforme", verdict_note: "OK" }
    assert delivery.reload.delivery_events.where(kind: "verdict").exists?

    get communication_path(brief)
    assert_response :success
    assert_select ".delivery-timeline"
    assert_match I18n.t("morocco.history.title", locale: :en), response.body
  end

  test "history locale keys exist without em dashes" do
    %i[fr en es ar].each do |locale|
      copy = I18n.t("morocco.history", locale: locale)
      assert copy[:title].present?
      DeliveryEvent::KINDS.each do |kind|
        assert copy[:kinds][kind.to_sym].present?, "#{locale} missing #{kind}"
      end
      flat = copy.values.flat_map { |value| value.is_a?(Hash) ? value.values : [ value ] }
      assert flat.none? { |value| value.to_s.include?("—") }
    end
  end
end
