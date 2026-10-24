require "test_helper"

class TaskReviewRecoveryUxTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("review-recovery", features: { morocco_ops: true })
    @task = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "A revoir", body_fr: "Corriger puis renvoyer", format: "task", status: "draft", requires_approval: true, requires_proof: true)
    @text = @task.communication_questions.create!(title_fr: "Observation", question_type: "short_text", required: true, position: 0)
    @choices = @task.communication_questions.create!(title_fr: "Choix", question_type: "multi_choice", position: 1, options: [ { label_fr: "Option A", label_ar: "الخيار أ" } ])
    @signature = @task.communication_questions.create!(title_fr: "Signature", question_type: "signature", position: 2)
    @task.send_to!([ @brand.store.id ])
    @delivery = @task.deliveries.first
    @delivery.update!(awareness: "in_progress")
  end

  test "unanswered multi-choice forms render in Morocco and legacy mode with explicit empty selection" do
    sign_in(@brand.store_user)
    [ true, false ].each do |morocco|
      @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => morocco))
      get inbox_path(@delivery)
      assert_response :success
      assert_select "input[type=checkbox][name='answers[#{@choices.id}][choices][]'][checked]", count: 0
      assert_select "input[type=checkbox][name='answers[#{@choices.id}][choices][]']", count: 1
      assert_select "input[type=hidden][name='answers[#{@choices.id}][choices][]'][value='']", count: 1
    end
  end

  test "pending approval shows submitted answers and signature read only in every locale" do
    submit_original
    %w[fr ar en es].each do |locale|
      get inbox_path(@delivery, locale: locale)
      assert_response :success
      assert_select ".task-card__answers", text: /Original answer/
      assert_select ".task-card__answers img[alt='Signature']", count: 1
      assert_select ".task-card__answers", text: locale == "ar" ? /الخيار أ/ : /Option A/
      assert_select "form.task-card__action", count: 0
      assert_select ".task-card__answers input, .task-card__answers textarea, .task-card__answers select", count: 0
      assert_select ".task-proof-gallery figcaption", text: "notes.txt"
    end
  end

  test "rejection retains proof and translated choices then correction can clear choices before approval" do
    submit_original
    proof_ids = @delivery.reload.proof_files.blobs.ids
    signature_id = @delivery.answer_for(@signature).image.blob.id
    sign_in(@brand.hq)
    post delivery_verdict_path(@delivery), params: { verdict: "non_conforme", verdict_note: "Refaire le facing" }
    assert_equal "pending", @delivery.reload.status

    sign_in(@brand.store_user)
    %w[fr ar].each do |locale|
      get inbox_path(@delivery, locale: locale)
      assert_select "input[name='answers[#{@text.id}][text]'][value='Original answer']"
      assert_select "input[type=checkbox][name='answers[#{@choices.id}][choices][]'][checked]", count: 1
      assert_select ".task-proof-gallery figcaption", text: "notes.txt"
      assert_match "Refaire le facing", response.body
    end
    post advance_inbox_path(@delivery), params: { step: "done", answers: { @text.id.to_s => { text: "Corrected answer" }, @choices.id.to_s => { choices: [ "" ] } } }
    assert_equal "pending_approval", @delivery.reload.status
    assert_empty @delivery.answer_for(@choices).reload.list_value
    assert_equal "Corrected answer", @delivery.answer_for(@text).reload.text_value
    assert_equal proof_ids, @delivery.proof_files.blobs.ids
    assert_equal signature_id, @delivery.answer_for(@signature).image.blob.id
    assert_nil @delivery.verdict
    assert_nil @delivery.verdict_note
    assert_equal "Refaire le facing", @delivery.delivery_events.find_by!(kind: "approval_rejected").payload["note"]

    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area, email: "area@review-recovery.test")
    sign_in(area)
    post delivery_verdict_path(@delivery), params: { verdict: "conforme", verdict_note: "Correction validee" }
    assert_equal "completed", @delivery.reload.status
    assert_equal area, @delivery.validated_by
    assert_equal 2, @delivery.delivery_events.where(kind: "approval_submitted").count
    assert_equal 1, @delivery.delivery_events.where(kind: "approval_rejected").count
    assert_equal 1, @delivery.delivery_events.where(kind: "approval_approved").count
    sign_in(@brand.store_user)
    get inbox_path(@delivery)
    assert_select ".task-card__answers", text: /Corrected answer/
    assert_select "form.task-card__action", count: 0
  end

  test "monitor-only roles keep evidence comments and existing corrective links without mutation controls" do
    submit_original
    monitor = create_user(@brand.tenant, org_unit: @brand.region, role: :area, email: "monitor@review-recovery.test")
    monitor.memberships.first.update!(tenant_role: @brand.tenant.tenant_roles.create!(name: "Read only", base_role: "area", capabilities: [ "monitor" ]))
    sign_in(monitor)
    assert_read_only_monitor
    post delivery_verdict_path(@delivery), params: { verdict: "conforme", verdict_note: "Denied" }
    assert_redirected_to app_root_path
    assert_equal "pending_approval", @delivery.reload.status

    @delivery.apply_verdict!("conforme", note: "Valide", by: @brand.hq)
    assert_read_only_monitor
    @delivery.apply_verdict!("non_conforme", note: "Refaire", by: @brand.hq)
    assert_read_only_monitor
    followup = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Correctif", body_fr: "Suivi", format: "task", status: "sent")
    @delivery.update!(corrective_communication: followup)
    get communication_path(@task)
    assert_select "a[href='#{communication_path(followup)}']", text: "Correctif"
    assert_select "form[action='#{delivery_corrective_action_path(@delivery)}']", count: 0
  end

  test "split review capabilities across memberships do not expose target-store reviewer controls" do
    submit_original
    monitor = create_user(@brand.tenant, org_unit: @brand.region, role: :area, email: "split@review-recovery.test")
    monitor.memberships.first.update!(tenant_role: @brand.tenant.tenant_roles.create!(name: "Verdict only", base_role: "area", capabilities: %w[monitor verdicts]))
    monitor.memberships.create!(org_unit: @brand.store, role: "area", tenant_role: @brand.tenant.tenant_roles.create!(name: "Escalate only", base_role: "area", capabilities: [ "escalate" ]))
    sign_in(monitor)
    assert_read_only_monitor
    post delivery_verdict_path(@delivery), params: { verdict: "conforme", verdict_note: "Denied" }
    assert_equal "pending_approval", @delivery.reload.status
  end

  test "authorized HQ area and acting platform admin retain reviewer controls" do
    submit_original
    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area, email: "reviewer@review-recovery.test")
    [ @brand.hq, area ].each do |reviewer|
      sign_in(reviewer)
      get communication_path(@task)
      assert_select "form[action='#{delivery_verdict_path(@delivery)}']", count: 1
    end
    foreign = build_brand("platform-review")
    admin = create_user(foreign.tenant, org_unit: foreign.region, role: :hq, email: "platform@review.test", super_admin: true)
    sign_in(admin, @brand.tenant)
    get communication_path(@task)
    assert_response :success
    assert_select "form[action='#{delivery_verdict_path(@delivery)}']", count: 1
  end

  test "unrelated store tenant and area cannot decide the task" do
    submit_original
    other_region = @brand.tenant.org_units.create!(name: "Other region", unit_type: "region")
    outsider = create_user(@brand.tenant, org_unit: other_region, role: :area, email: "outside@review-recovery.test")
    foreign = build_brand("review-other-tenant")
    [ @brand.store_user, outsider, foreign.hq ].each do |user|
      sign_in(user)
      post delivery_verdict_path(@delivery), params: { verdict: "conforme", verdict_note: "Denied" }
      assert_equal "pending_approval", @delivery.reload.status
      assert_nil @delivery.validated_by
    end
  end

  test "stored choice labels survive locale switches and unknown historical labels remain visible" do
    answer = @delivery.delivery_answers.create!(communication_question: @choices, value: { choices: [ "Option A" ] })
    assert answer.choice_selected?("الخيار أ", locale: :ar)
    assert_equal "الخيار أ", answer.display_value(locale: :ar)
    answer.update!(value: { choices: [ "الخيار أ" ] })
    assert answer.choice_selected?("Option A", locale: :fr)
    assert_equal "Option A", answer.display_value(locale: :fr)
    answer.update!(value: { choices: [ "Historical label" ] })
    assert_equal "Historical label", answer.display_value(locale: :ar)
  end

  test "clearing required choices is rejected without losing the previously submitted answer" do
    task = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Choix obligatoire", body_fr: "Selection requise", format: "task", status: "draft", requires_approval: true)
    question = task.communication_questions.create!(title_fr: "Choisir", question_type: "multi_choice", required: true, position: 0, options: [ { label_fr: "Option A", label_ar: "الخيار أ" } ])
    task.send_to!([ @brand.store.id ])
    delivery = task.deliveries.first
    delivery.update!(awareness: "in_progress")
    sign_in(@brand.store_user)
    post advance_inbox_path(delivery), params: { step: "done", answers: { question.id.to_s => { choices: [ "Option A" ] } } }
    assert_equal "pending_approval", delivery.reload.status
    delivery.apply_verdict!("non_conforme", note: "Revoir", by: @brand.hq)
    post advance_inbox_path(delivery), params: { step: "done", answers: { question.id.to_s => { choices: [ "" ] } } }, headers: { "Accept" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal "pending", delivery.reload.status
    assert_equal [ "Option A" ], delivery.answer_for(question).reload.list_value
  end

  private

  def submit_original
    sign_in(@brand.store_user)
    post advance_inbox_path(@delivery), params: {
      step: "done", proof_files: [ fixture_file_upload("notes.txt", "text/plain") ],
      answers: { @text.id.to_s => { text: "Original answer" }, @choices.id.to_s => { choices: [ "Option A" ] }, @signature.id.to_s => { image: fixture_file_upload("signature.png", "image/png") } }
    }
    assert_equal "pending_approval", @delivery.reload.status
  end

  def assert_read_only_monitor
    get communication_path(@task)
    assert_response :success
    assert_select "form[action='#{delivery_verdict_path(@delivery)}']", count: 0
    assert_select "form[action='#{delivery_corrective_action_path(@delivery)}']", count: 0
    assert_select ".brief-answers", text: /Original answer/
    assert_select ".delivery-comments"
  end
end
