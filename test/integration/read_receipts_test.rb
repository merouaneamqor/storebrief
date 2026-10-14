require "test_helper"

class ReadReceiptsTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "store user marks news as read and HQ sees unread counts" do
    brand = build_brand("atlas-reads", features: { morocco_ops: true })
    second = create_user(
      brand.tenant,
      org_unit: brand.store,
      role: :store,
      email: "store2@atlas-reads.test",
      name: "Store Two"
    )

    sign_in brand.hq
    post communications_path, params: {
      communication: {
        title_fr: "Hours update",
        body_fr: "New opening hours this week.",
        format: "news"
      },
      org_unit_ids: [ brand.store.id ],
      commit: "send"
    }
    brief = brand.tenant.communications.order(:id).last
    delivery = brief.deliveries.first
    assert_redirected_to communication_path(brief)

    get communication_path(brief)
    assert_response :success
    assert_match I18n.t("morocco.read_receipts.hq_unread_line", unread: 2, read: 0, total: 2, locale: :en), response.body
    assert_match I18n.t("morocco.read_receipts.store_unread", unread: 2, read: 0, total: 2, locale: :en), response.body

    delete logout_path
    follow_redirect!

    sign_in brand.store_user
    get inbox_path(delivery)
    assert_response :success
    assert_match I18n.t("morocco.read_receipts.unread_badge", locale: :en), response.body

    assert_difference -> { DeliveryRead.count }, 1 do
      post complete_inbox_path(delivery)
    end
    assert_redirected_to inbox_path(delivery)
    follow_redirect!
    assert_match I18n.t("morocco.read_receipts.you_read", locale: :en), response.body

    receipt = delivery.delivery_reads.find_by!(user: brand.store_user)
    assert_not_nil receipt.read_at
    assert_equal brand.tenant.id, receipt.tenant_id
    assert delivery.reload.read_by?(brand.store_user)
    assert_not delivery.read_by?(second)
    assert_equal "read", delivery.status

    delete logout_path
    follow_redirect!

    sign_in brand.hq
    get communication_path(brief)
    assert_response :success
    assert_match I18n.t("morocco.read_receipts.hq_unread_line", unread: 1, read: 1, total: 2, locale: :en), response.body
    assert_select "[data-testid=hq-unread-count]"
  end

  test "awareness read step records a per-user receipt" do
    brand = build_brand("atlas-reads-aware", features: { morocco_ops: true })
    communication = brand.tenant.communications.create!(
      author: brand.hq,
      format: "news",
      title_fr: "Planogram",
      body_fr: "Check the new planogram.",
      status: "sent"
    )
    delivery = communication.deliveries.create!(org_unit: brand.store, status: "pending", awareness: "pending")

    sign_in brand.store_user
    post advance_inbox_path(delivery), params: { step: "received" }
    assert_equal "received", delivery.reload.awareness
    assert_equal 0, delivery.delivery_reads.count

    assert_difference -> { DeliveryRead.count }, 1 do
      post advance_inbox_path(delivery), params: { step: "read" }
    end
    assert_equal "read", delivery.reload.awareness
    assert delivery.read_by?(brand.store_user)
  end

  test "marking read twice keeps a single receipt" do
    brand = build_brand("atlas-reads-once", features: { morocco_ops: true })
    communication = brand.tenant.communications.create!(
      author: brand.hq,
      format: "announcement",
      title_fr: "Ramadan",
      body_fr: "Updated hours.",
      status: "sent"
    )
    delivery = communication.deliveries.create!(org_unit: brand.store, status: "pending")

    sign_in brand.store_user
    assert_difference -> { DeliveryRead.count }, 1 do
      post complete_inbox_path(delivery)
    end
    assert_no_difference -> { DeliveryRead.count } do
      delivery.record_user_read!(brand.store_user)
    end
  end

  test "read receipt locales exist in fr en es ar" do
    %i[fr en es ar].each do |locale|
      I18n.with_locale(locale) do
        assert I18n.exists?("morocco.read_receipts.hq_unread_line")
        assert I18n.exists?("morocco.read_receipts.store_unread")
        assert I18n.exists?("morocco.read_receipts.unread_badge")
        assert I18n.exists?("morocco.read_receipts.you_read")
      end
    end
  end
end
