require "test_helper"

class OfflineWorkspacesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("offline-workspaces", features: { morocco_ops: true })
    @task = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Offline task", body_fr: "Do work", format: "task", status: "draft")
    @task.send_to!([ @brand.store.id ])
    @delivery = @task.deliveries.first
    @delivery.update!(awareness: "in_progress")
    sign_in @brand.store_user
  end

  test "authenticated HTML and fresh context carry the same private owner and session" do
    get inbox_path(@delivery)
    owner = "#{@brand.tenant.id}:#{@brand.store_user.id}"
    session_key = response.headers["X-Vazivo-Offline-Session"]
    assert_equal owner, response.headers["X-Vazivo-Offline-Owner"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_select "[data-offline-workspace]"
    get offline_context_path, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal owner, response.parsed_body["owner"]
    assert response.parsed_body["csrf_token"].present?
    assert_equal session_key, response.headers["X-Vazivo-Offline-Session"]
    delete logout_path
    get offline_context_path
    assert_redirected_to login_path
    sign_in @brand.store_user
    get inbox_path(@delivery)
    assert_not_equal session_key, response.headers["X-Vazivo-Offline-Session"]
  end

  test "stale queued task retains proof on client and changes nothing server side until resubmitted with current snapshot" do
    get inbox_path(@delivery)
    snapshot = css_select("input[name=task_snapshot]").first["value"]
    @task.update_columns(updated_at: 1.minute.from_now)
    request = { proof_request_id: "stale-once", proof_owner: "#{@brand.tenant.id}:#{@brand.store_user.id}", task_snapshot: snapshot,
                proof_files: [ fixture_file_upload("notes.txt", "text/plain") ] }
    post complete_inbox_path(@delivery), params: request, headers: { "Accept" => "application/json" }
    assert_response :conflict
    assert_equal "conflict", response.parsed_body["code"]
    assert_equal "pending", @delivery.reload.status
    assert_equal 0, @delivery.proof_files.count
    get inbox_path(@delivery)
    request[:task_snapshot] = css_select("input[name=task_snapshot]").first["value"]
    post complete_inbox_path(@delivery), params: request, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "completed", @delivery.reload.status
    post complete_inbox_path(@delivery), params: request, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal 1, @delivery.proof_files.count
  end

  test "another session owner cannot replay work even for a shared store delivery" do
    other_user = create_user(@brand.tenant, org_unit: @brand.store, role: :store, email: "other@offline.test")
    sign_in other_user
    post complete_inbox_path(@delivery), params: { proof_request_id: "wrong-owner", proof_owner: "#{@brand.tenant.id}:#{@brand.store_user.id}" }, headers: { "Accept" => "application/json" }
    assert_response :conflict
    assert_equal "pending", @delivery.reload.status
    sign_in @brand.store_user
    post complete_inbox_path(@delivery), params: { proof_request_id: "already-sent", proof_owner: "#{@brand.tenant.id}:#{@brand.store_user.id}" }, headers: { "Accept" => "application/json" }
    assert_response :success
    sign_in other_user
    post complete_inbox_path(@delivery), params: { proof_request_id: "already-sent", proof_owner: "#{@brand.tenant.id}:#{@brand.store_user.id}" }, headers: { "Accept" => "application/json" }
    assert_response :conflict
    foreign = build_brand("offline-foreign")
    sign_in foreign.store_user
    post complete_inbox_path(@delivery), params: { proof_request_id: "foreign-owner" }, headers: { "Accept" => "application/json" }
    assert_response :not_found
  end

  test "offline context is feature gated and translated banner renders" do
    %w[fr ar en es].each do |locale|
      get inbox_path(@delivery, locale: locale)
      assert_response :success
      assert_select "[data-offline-workspace][data-offline=?]", I18n.t("offline_workspaces.offline", locale: locale)
      assert_select "[data-offline-workspace][data-discard-confirm=?]", I18n.t("offline_workspaces.discard_confirm", locale: locale)
    end
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    get inbox_path(@delivery)
    assert_nil response.headers["X-Vazivo-Offline-Owner"]
    assert_select "[data-offline-workspace]", count: 0
    get offline_context_path
    assert_response :success
    @brand.tenant.update!(features: @brand.tenant.features.merge("briefs" => false))
    get offline_context_path
    assert_redirected_to app_root_path
  end
end
