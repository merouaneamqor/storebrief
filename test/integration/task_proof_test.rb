require "test_helper"

class TaskProofTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("task-proof")
    @task = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Vitrine", body_fr: "Preuve de la vitrine",
      format: "task", status: "draft", requires_proof: true
    )
    @task.send_to!([ @brand.store.id ])
    @delivery = @task.deliveries.first
    sign_in(@brand.store_user)
  end

  test "multiple files complete proof and are visible in the reviewer gallery" do
    post complete_inbox_path(@delivery), params: { proof_files: uploads }
    assert_redirected_to inbox_path(@delivery)
    assert_equal "completed", @delivery.reload.status
    assert_equal 2, @delivery.proof_files.count
    assert_equal 2, @delivery.delivery_events.find_by!(kind: "proof").payload["files"]

    get inbox_path(@delivery)
    assert_select ".task-proof-gallery figcaption a", count: 2
    assert_select ".task-proof-gallery img", count: 1

    sign_in(@brand.hq)
    get communication_path(@task)
    assert_response :success
    assert_select ".task-proof-gallery figcaption a", text: "notice.pdf"
    assert_select ".task-proof-gallery figcaption a", text: "window.jpg"
  end

  test "before and after photo proof remains supported" do
    post complete_inbox_path(@delivery), params: {
      photo_before: fixture_file_upload("window.jpg", "image/jpeg"),
      photo_after: fixture_file_upload("window.jpg", "image/jpeg")
    }
    assert_equal "completed", @delivery.reload.status
    assert @delivery.photo_before.attached?
    assert @delivery.photo_after.attached?
  end

  test "invalid upload rolls back all files and completion" do
    post complete_inbox_path(@delivery), params: {
      proof_files: [ fixture_file_upload("notice.pdf", "application/pdf"),
                     Rack::Test::UploadedFile.new(StringIO.new("<script>alert(1)</script>"), "text/html", original_filename: "proof.html") ]
    }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal "error", response.parsed_body["status"]
    assert_equal "pending", @delivery.reload.status
    assert_equal 0, @delivery.proof_files.count
    assert_equal 0, @delivery.delivery_events.where(kind: "proof").count
  end

  test "file size and total count are enforced on the model" do
    @delivery.proof_files = [ { io: StringIO.new("x"), filename: "large.pdf", content_type: "application/pdf", identify: false } ]
    @delivery.proof_files.first.blob.byte_size = Delivery::PROOF_MAX_BYTES + 1
    assert_not @delivery.valid?
    assert_includes @delivery.errors.full_messages.join, I18n.t("task_proof.too_large", size: 10, locale: :en)

    @delivery.proof_files = Array.new(Delivery::PROOF_MAX_COUNT + 1) do |index|
      { io: StringIO.new("x"), filename: "proof-#{index}.txt", content_type: "text/plain" }
    end
    assert_not @delivery.valid?
    assert_includes @delivery.errors.full_messages.join, I18n.t("task_proof.too_many", count: 10, locale: :en)
  end

  test "a retried offline multipart submission cannot duplicate proof" do
    2.times do
      post complete_inbox_path(@delivery), params: {
        proof_request_id: "offline-unique-123", proof_files: uploads
      }, headers: { "Accept" => "application/json" }
      assert_response :success
      assert_equal "ok", response.parsed_body["status"]
    end
    assert_equal "completed", @delivery.reload.status
    assert_equal 2, @delivery.proof_files.count
    assert_equal 1, @delivery.delivery_events.where(kind: "proof").count
  end

  test "offline advance retry preserves approval submission and rejects missing proof" do
    @task.update!(requires_approval: true)
    @delivery.update!(awareness: "in_progress")
    post advance_inbox_path(@delivery), params: { step: "done", proof_request_id: "retry-done" },
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal "pending", @delivery.reload.status

    2.times do
      post advance_inbox_path(@delivery), params: {
        step: "done", proof_request_id: "retry-done", proof_files: uploads
      }, headers: { "Accept" => "application/json" }
      assert_response :success
      assert_equal "pending_approval", response.parsed_body["delivery_status"]
    end
    assert_equal 2, @delivery.reload.proof_files.count
    assert_equal 1, @delivery.delivery_events.where(kind: "approval_submitted").count
  end

  test "ordinary awareness progress does not claim completion or duplicate proof history" do
    @delivery.proof_files.attach(fixture_file_upload("notice.pdf", "application/pdf"))
    post advance_inbox_path(@delivery), params: { step: "received" }
    assert_redirected_to inbox_path(@delivery)
    assert_equal I18n.t("morocco.awareness.saved", locale: :en), flash[:notice]
    assert_equal "pending", @delivery.reload.status
    assert_equal 0, @delivery.delivery_events.where(kind: "proof").count
  end

  test "store cannot submit proof for another store or tenant" do
    other_store = @brand.tenant.org_units.create!(name: "Other", unit_type: "store", parent: @brand.region)
    foreign = @task.deliveries.create!(org_unit: other_store, status: "pending")
    post complete_inbox_path(foreign), params: { proof_files: uploads }, headers: { "Accept" => "application/json" }
    assert_response :not_found
    assert_equal 0, foreign.proof_files.count
    assert_equal "pending", foreign.reload.status
  end

  test "signed blob references cannot import proof from another tenant" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("private"), filename: "private.txt", content_type: "text/plain")
    post complete_inbox_path(@delivery), params: { proof_files: [ blob.signed_id ] },
         headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal 0, @delivery.reload.proof_files.count
  ensure
    blob&.purge
  end

  test "proof form exposes multi-file limits and offline owner context" do
    @delivery.update!(awareness: "in_progress")
    get inbox_path(@delivery)
    assert_response :success
    assert_select "form[data-task-proof=true][data-turbo=false] input[name='proof_files[]'][multiple]"
    assert_select "fieldset[data-max-bytes='#{Delivery::PROOF_MAX_BYTES}'][data-max-count='10']"
    assert_select "meta[name=task-proof-owner][content='#{@brand.tenant.id}:#{@brand.store_user.id}']"
  end

  private

  def uploads
    [ fixture_file_upload("notice.pdf", "application/pdf"), fixture_file_upload("window.jpg", "image/jpeg") ]
  end
end
