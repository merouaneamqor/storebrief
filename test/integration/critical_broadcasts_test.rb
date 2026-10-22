require "test_helper"

class CriticalBroadcastsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("broadcasts", features: { email_alerts: false })
  end

  test "HQ sends an urgent critical announcement and store explicitly acknowledges it once" do
    sign_in(@brand.hq)
    get new_communication_path
    assert_select "input[name='communication[critical_broadcast]']"

    post communications_path, params: {
      communication: {
        title_fr: "Rappel de sécurité", body_fr: "Vérifiez les sorties.", format: "announcement",
        critical_broadcast: "1", requires_acknowledgement: "1"
      },
      org_unit_ids: [ @brand.store.id ], commit: "send"
    }
    broadcast = @brand.tenant.communications.order(:id).last
    assert broadcast.critical_broadcast?
    assert broadcast.requires_acknowledgement?
    assert_equal "urgent", broadcast.priority
    delivery = broadcast.deliveries.sole

    delete logout_path
    sign_in(@brand.store_user)
    get app_root_path
    assert_select "#broadcasts-title", text: "Critical broadcasts"
    assert_select "a[href='#{inbox_path(delivery)}']", text: broadcast.title_fr
    get inbox_path(delivery)
    assert_select "form[action='#{broadcast_acknowledgement_path(delivery)}']"

    # Existing read flow cannot silently satisfy a required acknowledgement.
    post complete_inbox_path(delivery)
    assert_nil delivery.reload.acknowledged_at
    get app_root_path
    assert_select "#broadcasts-title"

    assert_difference -> { delivery.delivery_events.where(kind: "acknowledged").count }, 1 do
      post broadcast_acknowledgement_path(delivery)
      assert_redirected_to inbox_path(delivery)
      post broadcast_acknowledgement_path(delivery)
    end
    assert delivery.reload.acknowledged_at
    assert_equal @brand.store_user, delivery.acknowledged_by
    assert delivery.read_by?(@brand.store_user)
    get app_root_path
    assert_select "#broadcasts-title", count: 0
  end

  test "acknowledging an unread broadcast records the first store actor and read receipt" do
    broadcast = create_broadcast
    delivery = broadcast.deliveries.sole
    sign_in(@brand.store_user)
    post broadcast_acknowledgement_path(delivery)
    assert_redirected_to inbox_path(delivery)
    assert_equal "read", delivery.reload.status
    assert delivery.read_by?(@brand.store_user)
    first_at = delivery.acknowledged_at
    second_user = create_user(@brand.tenant, org_unit: @brand.store, role: :store, email: "second@broadcasts.test")
    delete logout_path
    sign_in(second_user)
    post broadcast_acknowledgement_path(delivery)
    assert_equal @brand.store_user.id, delivery.reload.acknowledged_by_id
    assert_equal first_at, delivery.acknowledged_at
    assert_equal 1, delivery.delivery_events.where(kind: "acknowledged").count

    delete logout_path
    sign_in(@brand.hq)
    get communication_path(broadcast)
    assert_response :success
    assert_select "#store-#{@brand.store.id}", text: /Acknowledged by the store/
  end

  test "other stores and HQ cannot acknowledge a store broadcast" do
    broadcast = create_broadcast
    delivery = broadcast.deliveries.sole
    other_store = @brand.tenant.org_units.create!(name: "Other", unit_type: "store", parent: @brand.region)
    other_user = create_user(@brand.tenant, org_unit: other_store, role: :store, email: "other@broadcasts.test")
    sign_in(other_user)
    post broadcast_acknowledgement_path(delivery)
    assert_response :not_found
    assert_nil delivery.reload.acknowledged_at
    get app_root_path
    assert_select "#broadcasts-title", count: 0

    delete logout_path
    sign_in(@brand.hq)
    post broadcast_acknowledgement_path(delivery)
    assert_response :not_found
    assert_nil delivery.reload.acknowledged_at
  end

  test "another tenant and disabled Morocco operations cannot acknowledge the broadcast" do
    delivery = create_broadcast.deliveries.sole
    other = build_brand("broadcast-other")
    sign_in(other.store_user)
    post broadcast_acknowledgement_path(delivery)
    assert_response :not_found
    assert_nil delivery.reload.acknowledged_at

    delete logout_path
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    sign_in(@brand.store_user)
    post broadcast_acknowledgement_path(delivery)
    assert_redirected_to app_root_path
    assert_nil delivery.reload.acknowledged_at
  end

  test "broadcast without acknowledgement unpins after reading and is always above future tasks" do
    broadcast = create_broadcast(requires_acknowledgement: false, due_at: 2.weeks.from_now)
    sign_in(@brand.store_user)
    get app_root_path
    assert_select "#broadcasts-title"
    post complete_inbox_path(broadcast.deliveries.sole)
    get app_root_path
    assert_select "#broadcasts-title", count: 0
  end

  test "broadcast compose settings and Arabic radar are translated" do
    sign_in(@brand.hq)
    %w[fr en es ar].each do |locale|
      get new_communication_path, params: { locale: locale }
      assert_response :success
      assert_select "input[name='communication[requires_acknowledgement]']"
      assert_no_match(/translation_missing|Translation missing/, response.body)
    end
    create_broadcast
    delete logout_path
    @brand.store_user.update!(locale: "ar")
    sign_in(@brand.store_user)
    get app_root_path
    assert_select "html[dir=rtl]"
    assert_select "#broadcasts-title", text: I18n.t("broadcasts.pinned", locale: :ar)
  end

  private

  def create_broadcast(**attrs)
    @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Alerte sécurité", body_fr: "Vérifiez les sorties.",
      format: "announcement", critical_broadcast: true, requires_acknowledgement: true, **attrs
    ).tap { |broadcast| broadcast.send_to!([ @brand.store.id ]) }
  end
end
