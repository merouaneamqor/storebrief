require "test_helper"

class TaskMediaTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("task-media", features: { morocco_ops: true })
    @task = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Signed audit", body_fr: "Sign", format: "task", status: "draft")
    @question = @task.communication_questions.create!(title_fr: "Signature", question_type: "signature", position: 0, required: true)
    @task.send_to!([ @brand.store.id ])
    @delivery = @task.deliveries.first
    sign_in @brand.store_user
  end

  test "signature PNG and task video survive replay and appear in review and audit history" do
    post complete_inbox_path(@delivery), params: media_params, headers: { "Accept" => "application/json" }
    assert_response :success
    answer = @delivery.delivery_answers.first
    assert_equal "image/png", answer.image.blob.content_type
    assert_equal "completed", @delivery.reload.status
    post complete_inbox_path(@delivery), params: media_params, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal 1, @delivery.proof_files.count
    assert_equal 1, @delivery.delivery_answers.count
    sign_in @brand.hq
    get communication_path(@task)
    assert_select "video[controls]", count: 1
    assert_select ".brief-answers img", count: 1
    get audit_history_path
    assert_response :success
    assert_select "details video[controls]", count: 1
    assert_select "details img", count: 1
  end

  test "required signature rejects missing or non PNG attachment and rolls back video" do
    params = media_params
    params.delete(:answers)
    post complete_inbox_path(@delivery), params: params, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal 0, @delivery.reload.proof_files.count
    params = media_params
    params[:answers][@question.id.to_s][:image] = fixture_file_upload("window.jpg", "image/jpeg")
    post complete_inbox_path(@delivery), params: params, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal 0, @delivery.delivery_answers.count
  end

  test "video bounds and legacy photo image restriction are enforced" do
    @delivery.proof_files = [ { io: StringIO.new("video"), filename: "clip.webm", content_type: "video/webm", identify: false } ]
    @delivery.proof_files.first.blob.byte_size = Delivery::PROOF_VIDEO_MAX_BYTES
    assert @delivery.valid?
    @delivery.proof_files.first.blob.byte_size += 1
    assert_not @delivery.valid?
    @delivery.proof_files = []
    @delivery.photo_before = { io: StringIO.new("video"), filename: "clip.webm", content_type: "video/webm", identify: false }
    assert_not @delivery.valid?
  end

  test "tenant store roles and feature flag protect task media" do
    other = build_brand("task-media-foreign")
    sign_in other.store_user
    post complete_inbox_path(@delivery), params: media_params
    assert_response :not_found
    sign_in @brand.hq
    post complete_inbox_path(@delivery), params: media_params
    assert_redirected_to app_root_path
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    @delivery.proof_files = [ { io: StringIO.new("video"), filename: "clip.webm", content_type: "video/webm", identify: false } ]
    assert_not @delivery.valid?
  end

  test "signature pad and video limits render in four locales" do
    @delivery.update!(awareness: "in_progress")
    %w[fr ar en es].each do |locale|
      get inbox_path(@delivery, locale: locale)
      assert_response :success
      assert_select "[data-signature-pad] canvas"
      assert_select "input[data-signature-file][accept='image/png']"
      assert_select "fieldset[data-video-max-bytes='#{Delivery::PROOF_VIDEO_MAX_BYTES}']"
      assert_match I18n.t("task_media.sign_hint", locale: locale), response.body
    end
  end

  private

  def media_params
    { proof_request_id: "signature-video-once", proof_files: [ fixture_file_upload("clip.webm", "video/webm") ],
      answers: { @question.id.to_s => { image: fixture_file_upload("signature.png", "image/png") } } }
  end
end
