require "test_helper"

class ApprovalWorkflowTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("approval-ma")
  end

  test "store submits for approval and completion does not count as done" do
    brief = approval_task
    delivery = brief.deliveries.first
    sign_in(@brand.store_user)

    %w[received read understood in_progress].each do |step|
      post advance_inbox_path(delivery), params: { step: step }
      assert_redirected_to inbox_path(delivery)
    end

    post advance_inbox_path(delivery), params: { step: "done" }
    assert_redirected_to inbox_path(delivery)
    follow_redirect!
    assert_match I18n.t("morocco.approval.submitted", locale: :en), response.body

    delivery.reload
    assert_equal "pending_approval", delivery.status
    assert_equal "in_progress", delivery.awareness
    assert_nil delivery.completed_at
    assert_not delivery.finished?
    assert_equal "awaiting", delivery.tone
    assert delivery.delivery_events.where(kind: "approval_submitted").exists?

    get inbox_path(delivery)
    assert_response :success
    assert_match I18n.t("morocco.approval.waiting_title", locale: :en), response.body
    assert_select "button", text: I18n.t("morocco.approval.submit", locale: :en), count: 0
  end

  test "hq approves with note and task becomes completed" do
    brief = approval_task
    delivery = brief.deliveries.first
    advance_to_submit!(delivery)

    sign_in(@brand.hq)
    get communication_path(brief)
    assert_response :success
    assert_match I18n.t("morocco.approval.decide", locale: :en), response.body

    post delivery_verdict_path(delivery), params: { verdict: "conforme", verdict_note: "Vitrine OK." }
    assert_redirected_to communication_path(brief)
    follow_redirect!
    assert_match I18n.t("morocco.approval.approved", locale: :en), response.body

    delivery.reload
    assert_equal "completed", delivery.status
    assert_equal "done", delivery.awareness
    assert_equal "conforme", delivery.verdict
    assert_equal "Vitrine OK.", delivery.verdict_note
    assert delivery.completed_at.present?
    assert delivery.finished?
    assert delivery.delivery_events.where(kind: "approval_approved").exists?
  end

  test "hq reject without note is blocked and reject returns to in_progress" do
    brief = approval_task
    delivery = brief.deliveries.first
    advance_to_submit!(delivery)

    sign_in(@brand.hq)
    post delivery_verdict_path(delivery),
         params: { verdict: "non_conforme", verdict_note: "" },
         headers: { "HTTP_REFERER" => communication_path(brief) }
    assert_redirected_to communication_path(brief)
    follow_redirect!
    assert_match I18n.t("morocco.approval.note_required", locale: :en), response.body
    assert_equal "pending_approval", delivery.reload.status

    post delivery_verdict_path(delivery),
         params: { verdict: "non_conforme", verdict_note: "Refaire le facing." },
         headers: { "HTTP_REFERER" => communication_path(brief) }
    assert_redirected_to communication_path(brief)
    follow_redirect!
    assert_match I18n.t("morocco.approval.rejected", locale: :en), response.body

    delivery.reload
    assert_equal "pending", delivery.status
    assert_equal "in_progress", delivery.awareness
    assert_equal "non_conforme", delivery.verdict
    assert_equal "Refaire le facing.", delivery.verdict_note
    assert_nil delivery.completed_at
    assert_not delivery.finished?
    assert delivery.delivery_events.where(kind: "approval_rejected").exists?

    sign_in(@brand.store_user)
    get inbox_path(delivery)
    assert_response :success
    assert_match I18n.t("morocco.approval.rejected_title", locale: :en), response.body
    assert_match "Refaire le facing.", response.body
    assert_select "button", text: I18n.t("morocco.approval.submit", locale: :en)
  end

  test "area manager can approve a store in their area" do
    area = @brand.tenant.org_units.create!(name: "Casa Area", unit_type: "area", parent: @brand.region)
    @brand.store.update!(parent: area)
    area_user = create_user(@brand.tenant, org_unit: area, role: :area, email: "area@approval-ma.test")

    brief = approval_task
    delivery = brief.deliveries.first
    advance_to_submit!(delivery)

    sign_in(area_user)
    post delivery_verdict_path(delivery), params: { verdict: "improve", verdict_note: "Ajuster l'éclairage." }
    assert_redirected_to communication_path(brief)

    delivery.reload
    assert_equal "completed", delivery.status
    assert_equal "improve", delivery.verdict
    assert_equal "Ajuster l'éclairage.", delivery.verdict_note
  end

  test "tasks without approval still complete immediately" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Sans validation",
      body_fr: "Fermer normalement.",
      format: "task",
      status: "draft",
      source: "compose",
      requires_approval: false
    ).tap { |c| c.send_to!([ @brand.store.id ]) }
    delivery = brief.deliveries.first
    sign_in(@brand.store_user)

    %w[received read understood in_progress done].each do |step|
      post advance_inbox_path(delivery), params: { step: step }
    end

    delivery.reload
    assert_equal "completed", delivery.status
    assert_equal "done", delivery.awareness
    assert delivery.finished?
  end

  private

  def approval_task
    @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Vitrine à valider",
      title_ar: "واجهة للموافقة",
      body_fr: "Soumettre pour validation HQ.",
      body_ar: "أرسل للموافقة.",
      format: "task",
      status: "draft",
      source: "compose",
      requires_approval: true,
      requires_proof: false
    ).tap { |brief| brief.send_to!([ @brand.store.id ]) }
  end

  def advance_to_submit!(delivery)
    sign_in(@brand.store_user)
    %w[received read understood in_progress done].each do |step|
      post advance_inbox_path(delivery), params: { step: step }
    end
    assert_equal "pending_approval", delivery.reload.status
  end
end
