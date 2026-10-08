require "test_helper"

class SyncTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("atlas-sync")
    checklist = @brand.tenant.checklists.create!(author: @brand.hq, title_fr: "Ouverture", status: "draft")
    @alarm = checklist.checklist_items.create!(position: 0, title_fr: "Alarmes", requires_photo: false)
    @window = checklist.checklist_items.create!(position: 1, title_fr: "Vitrine", requires_photo: true)
    checklist.send_to!([ @brand.store.id ])
    @delivery = checklist.checklist_deliveries.first
  end

  test "offline queue flush saves responses, photos, and completes the delivery" do
    sign_in(@brand.store_user)

    post sync_checklist_responses_path, as: :json, params: {
      responses: [
        { delivery_id: @delivery.id, item_id: @alarm.id, completed: true, notes: "fait", client_uuid: "uuid-1" },
        { delivery_id: @delivery.id, item_id: @window.id, completed: true, client_uuid: "uuid-2", photo_data: photo_data_uri }
      ]
    }

    assert_response :success
    results = response.parsed_body["results"]
    assert_equal %w[uuid-1 uuid-2], results.map { |r| r["client_uuid"] }
    assert_equal %w[ok ok], results.map { |r| r["status"] }
    assert_equal "completed", results.last["delivery_status"]

    assert @delivery.reload.completed?
    window_response = @delivery.checklist_item_responses.find_by(checklist_item: @window)
    assert window_response.photo.attached?
    assert_equal "image/jpeg", window_response.photo.content_type
    assert_equal "fait", @delivery.checklist_item_responses.find_by(checklist_item: @alarm).notes
  end

  test "replaying the same queue does not duplicate responses" do
    sign_in(@brand.store_user)
    payload = { responses: [ { delivery_id: @delivery.id, item_id: @alarm.id, completed: true, client_uuid: "uuid-1" } ] }

    2.times { post sync_checklist_responses_path, as: :json, params: payload }

    assert_equal 1, @delivery.checklist_item_responses.count
    assert @delivery.reload.pending?
  end

  test "entries for another brand's delivery are ignored" do
    other = build_brand("contoso-sync")
    sign_in(other.store_user)

    post sync_checklist_responses_path, as: :json, params: {
      responses: [ { delivery_id: @delivery.id, item_id: @alarm.id, completed: true, client_uuid: "uuid-x" } ]
    }

    assert_response :success
    assert_equal [], response.parsed_body["results"]
    assert_equal 0, @delivery.checklist_item_responses.count
  end

  test "sync requires a signed-in user" do
    post sync_checklist_responses_path, as: :json, params: { responses: [] }
    assert_redirected_to login_path
  end

  private

  def photo_data_uri
    "data:image/jpeg;base64,#{Base64.strict_encode64(file_fixture('window.jpg').binread)}"
  end
end
