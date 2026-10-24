require "test_helper"

class TaskAuthoringRecoveryTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("authoring-ux", features: { morocco_ops: true })
    @brand.hq.update!(locale: "fr")
    sign_in(@brand.hq)
  end

  test "editing an attached task has only attachment controls in its attachment rows" do
    task = @brand.tenant.communications.create!(author: @brand.hq, format: "task", title_fr: "Promo", body_fr: "Read the attachment", status: "draft")
    task.attachments.attach(fixture_file_upload("notice.pdf", "application/pdf"))
    get edit_communication_path(task)
    assert_response :success
    assert_select ".brief-attachments", text: /notice\.pdf/
    assert_select ".brief-attachments input[type=checkbox][name='communication[remove_attachment_ids][]']", count: 1
    assert_select ".brief-attachments input[required]", count: 0
    assert_select ".brief-attachments [x-model='question.weight']", count: 0
  end
  test "draft recipient choice and filters survive saving and reopening the editor" do
    @brand.store.update!(store_format: "express", cluster_key: "north")
    post communications_path, params: {
      communication: { title_fr: "Chosen audience", body_fr: "Send to the intended stores", format: "task" },
      org_unit_ids: [ @brand.region.id ], assignment_role: "store", store_format: "express", cluster: "north", commit: "draft"
    }
    task = @brand.tenant.communications.order(:id).last
    assert_redirected_to edit_communication_path(task)
    follow_redirect!
    assert_select ".brief-targets-block[data-selected=?]", [ @brand.region.id.to_s ].to_json
    assert_select ".brief-targets-block[data-assignment-role='store'][data-store-format='express'][data-cluster='north']"
  end

  test "invalid content retains selected recipients and assignment filters" do
    post communications_path, params: {
      communication: { title_fr: "", body_fr: "Retain my choices", format: "task" },
      org_unit_ids: [ @brand.region.id ], assignment_role: "store", store_format: "express", cluster: "north", commit: "draft"
    }
    assert_response :unprocessable_entity
    assert_select ".brief-targets-block[data-selected=?]", [ @brand.region.id.to_s ].to_json
    assert_select ".brief-targets-block[data-assignment-role='store'][data-store-format='express'][data-cluster='north']"
  end

  test "clearing recipients does not restore the previous audience or permit an empty review" do
    task = create_targeted_draft
    patch communication_path(task), params: { communication: { body_fr: "Cleared" }, org_unit_ids: [ "" ], commit: "draft" }
    assert_empty task.reload.targeting["org_unit_ids"]
    @brand.tenant.update!(features: @brand.tenant.features.merge("send_approval" => true))
    post send_brief_communication_path(task)
    assert_redirected_to edit_communication_path(task)
    assert_equal I18n.t("errors.select_targets", locale: :fr), flash[:alert]
    assert_nil task.reload.review_status
    assert_empty task.deliveries
  end

  test "foreign or malformed recipients cannot be saved or silently broaden the audience" do
    foreign = build_brand("foreign-authoring")
    [ [ foreign.store.id.to_s ], [ @brand.store.id.to_s, foreign.store.id.to_s ], [ "not-a-unit" ] ].each do |ids|
      assert_no_difference "Communication.count" do
        post communications_path, params: {
          communication: { title_fr: "Unsafe audience", body_fr: "Do not send", format: "task" },
          org_unit_ids: ids, commit: "send"
        }
      end
      assert_response :unprocessable_entity
      assert_includes response.body, I18n.t("errors.invalid_targets", locale: :fr)
    end
  end

  test "rejection correction approval and send retain the reviewed audience" do
    @brand.tenant.update!(features: @brand.tenant.features.merge("send_approval" => true))
    task = create_targeted_draft(commit: "send")
    assert task.review_pending?
    expected = task.targeting
    approver = create_user(@brand.tenant, org_unit: @brand.region, role: :hq, email: "reviewer@authoring-ux.test")
    sign_in(approver)
    post reject_communication_path(task), params: { review_note: "Clarify instructions" }
    assert task.reload.review_rejected?
    get edit_communication_path(task)
    assert_select ".brief-targets-block[data-selected=?]", [ @brand.region.id.to_s ].to_json
    sign_in(@brand.hq)
    patch communication_path(task), params: { communication: { body_fr: "Clearer instructions" }, commit: "send" }
    assert task.reload.review_pending?
    assert_equal expected, task.targeting
    sign_in(approver)
    post approve_communication_path(task)
    assert task.reload.review_approved?
    sign_in(@brand.hq)
    post send_brief_communication_path(task)
    assert task.reload.sent?
    assert_equal [ @brand.store.id ], task.deliveries.pluck(:org_unit_id)
    assert_equal %w[submitted rejected submitted approved], task.approval_events.order(:id).pluck(:kind)
  end

  test "changing approved recipients forces a new review before delivery" do
    @brand.tenant.update!(features: @brand.tenant.features.merge("send_approval" => true))
    task = create_targeted_draft(commit: "send")
    approve(task)
    alternate = @brand.tenant.org_units.create!(name: "Alternate", unit_type: "store", parent: @brand.region)
    post send_brief_communication_path(task), params: { org_unit_ids: [ alternate.id ] }
    assert task.reload.review_pending?
    assert task.draft?
    assert_empty task.deliveries
    assert_equal [ alternate.id.to_s ], task.targeting["org_unit_ids"]
  end

  test "newly matching stores cannot silently expand an approved region" do
    @brand.tenant.update!(features: @brand.tenant.features.merge("send_approval" => true))
    task = create_targeted_draft(commit: "send")
    approve(task)
    alternate = @brand.tenant.org_units.create!(name: "New store", unit_type: "store", parent: @brand.region)
    post send_brief_communication_path(task)
    assert task.reload.review_pending?
    assert_empty task.deliveries
    assert_equal [ @brand.store.id, alternate.id ].sort, task.targeting["store_ids"]
  end

  test "approved legacy draft must review its first explicit audience before sending" do
    @brand.tenant.update!(features: @brand.tenant.features.merge("send_approval" => true))
    task = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Legacy", body_fr: "Needs audience review", format: "task")
    Vazivo::Approval.submit!(task, actor: @brand.hq)
    approve(task)
    post send_brief_communication_path(task), params: { org_unit_ids: [ @brand.store.id ] }
    assert task.reload.review_pending?
    assert_empty task.deliveries
  end

  test "a forged assignment role cannot be saved" do
    assert_no_difference "Communication.count" do
      post communications_path, params: {
        communication: { title_fr: "Invalid role", body_fr: "No send", format: "task" },
        org_unit_ids: [ @brand.store.id ], assignment_role: "super_admin", commit: "send"
      }
    end
    assert_response :unprocessable_entity
  end

  test "direct sending cannot replace a reviewed recipient snapshot" do
    @brand.tenant.update!(features: @brand.tenant.features.merge("send_approval" => true))
    task = create_targeted_draft(commit: "send")
    approve(task)
    alternate = @brand.tenant.org_units.create!(name: "Unreviewed", unit_type: "store", parent: @brand.region)
    assert_raises(Vazivo::Approval::Required) { task.send_to!([ alternate.id ]) }
    task.assign_targeting(org_unit_ids: [ alternate.id ])
    assert_raises(Vazivo::Approval::Required) { task.send_to!([ alternate.id ]) }
    assert_empty task.deliveries
  end

  private

  def create_targeted_draft(commit: "draft")
    post communications_path, params: {
      communication: { title_fr: "Preserved audience", body_fr: "Follow the instructions", format: "task" },
      org_unit_ids: [ @brand.region.id ], commit: commit
    }
    @brand.tenant.communications.order(:id).last
  end

  def approve(task)
    user = create_user(@brand.tenant, org_unit: @brand.region, role: :hq, email: "reviewer@authoring-ux.test")
    Vazivo::Approval.decide!(task, approver: user, decision: "approved")
  end
end
