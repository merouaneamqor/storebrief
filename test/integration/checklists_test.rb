require "test_helper"

class ChecklistsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("atlas-checklists")
    @template = @brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Ouverture magasin",
      title_ar: "افتتاح المتجر",
      items: [
        { title_fr: "Alarmes désactivées", requires_photo: false },
        { title_fr: "Photo de la vitrine", requires_photo: true }
      ]
    )
  end

  test "hq turns a template into a draft and sends it to a region" do
    sign_in(@brand.hq)

    get templates_path
    assert_response :success
    assert_select "form[action=?]", use_template_path(@template)

    assert_difference -> { @brand.tenant.checklists.count }, 1 do
      post use_template_path(@template)
    end
    checklist = @brand.tenant.checklists.order(:id).last
    assert_redirected_to checklist_path(checklist)
    assert checklist.draft?
    assert_equal [ "Alarmes désactivées", "Photo de la vitrine" ], checklist.checklist_items.map(&:title_fr)

    follow_redirect!
    assert_response :success

    post send_checklist_checklist_path(checklist), params: { org_unit_ids: [ @brand.region.id ] }
    assert_redirected_to checklist_path(checklist)
    assert_equal I18n.t("checklists.sent", locale: :en), flash[:notice]
    assert checklist.reload.sent?
    assert_equal [ @brand.store.id ], checklist.checklist_deliveries.pluck(:org_unit_id)

    post send_checklist_checklist_path(checklist), params: { org_unit_ids: [ @brand.region.id ] }
    assert_equal I18n.t("communications.already_sent", locale: :en), flash[:alert]
    assert_equal 1, checklist.checklist_deliveries.count
  end

  test "sending without targets keeps the checklist as a draft" do
    checklist = Checklist.build_from_template(@template, author: @brand.hq)
    checklist.save!
    sign_in(@brand.hq)

    post send_checklist_checklist_path(checklist), params: { org_unit_ids: [] }
    assert_redirected_to checklist_path(checklist)
    assert_equal I18n.t("errors.select_targets", locale: :en), flash[:alert]
    assert checklist.reload.draft?
  end

  test "store ticks items and the delivery completes once the photo is in" do
    delivery = send_template_checklist
    alarm, photo_item = delivery.checklist.checklist_items.to_a
    sign_in(@brand.store_user)

    get checklists_deliveries_path
    assert_response :success
    assert_select "a[href=?]", checklists_delivery_path(delivery)

    get checklists_delivery_path(delivery)
    assert_response :success

    post submit_item_checklists_delivery_path(delivery), params: { item_id: alarm.id, notes: "OK" }
    assert_redirected_to checklists_delivery_path(delivery)
    assert delivery.reload.pending?

    # Photo item ticked without a photo does not complete the delivery
    post submit_item_checklists_delivery_path(delivery), params: { item_id: photo_item.id }
    assert delivery.reload.pending?

    post submit_item_checklists_delivery_path(delivery), params: {
      item_id: photo_item.id,
      photo: fixture_file_upload("window.jpg", "image/jpeg")
    }
    assert delivery.reload.completed?
    assert delivery.checklist_item_responses.find_by(checklist_item: photo_item).photo.attached?
    assert_equal({ total: 1, done: 1, pending: 0, percent: 100 }, delivery.checklist.completion_stats)
  end

  test "store can finish the whole checklist at once" do
    delivery = send_template_checklist
    sign_in(@brand.store_user)

    post complete_checklists_delivery_path(delivery)
    assert_redirected_to checklists_delivery_path(delivery)
    assert delivery.reload.completed?
    assert_equal 2, delivery.checklist_item_responses.where(completed: true).count
  end

  test "a store cannot open another brand's checklist delivery" do
    delivery = send_template_checklist
    other = build_brand("contoso-checklists")
    sign_in(other.store_user)

    get checklists_delivery_path(delivery)
    assert_response :not_found
  end

  test "store users cannot reach the hq checklist screens" do
    sign_in(@brand.store_user)

    get checklists_path
    assert_redirected_to app_root_path
    post use_template_path(@template)
    assert_redirected_to app_root_path
  end

  private

  def send_template_checklist
    checklist = Checklist.build_from_template(@template, author: @brand.hq)
    checklist.save!
    checklist.send_to!([ @brand.store.id ])
    checklist.checklist_deliveries.first
  end
end
