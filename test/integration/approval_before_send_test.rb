require "test_helper"

class ApprovalBeforeSendTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("approval-gate", features: { "send_approval" => true })
    @tenant = @brand.tenant
    @author = @brand.hq
    @approver = create_user(@tenant, org_unit: @brand.region, role: :hq, email: "approver@approval-gate.test")
    @area_user = create_user(@tenant, org_unit: @brand.region, role: :area, email: "area@approval-gate.test")
  end

  def draft_brief(author: @author, tenant: @tenant)
    tenant.communications.create!(author: author, title_fr: "Promo", body_fr: "Mettre la PLV",
                                  format: "news", status: "draft")
  end

  # -- default off ---------------------------------------------------------

  test "approval is off by default and sending is unchanged" do
    brand = build_brand("approval-off")
    assert_not Vazivo::Approval.required?(brand.tenant)

    brief = draft_brief(author: brand.hq, tenant: brand.tenant)
    brief.send_to!([ brand.store.id ])
    assert brief.reload.sent?
  end

  # -- the gate ------------------------------------------------------------

  test "send_to! is blocked server-side until approved" do
    brief = draft_brief

    assert_raises(Vazivo::Approval::Required) { brief.send_to!([ @brand.store.id ]) }
    assert brief.reload.draft?
    assert_equal 0, brief.deliveries.count

    Vazivo::Approval.submit!(brief, actor: @author)
    assert_raises(Vazivo::Approval::Required) { brief.send_to!([ @brand.store.id ]) }

    Vazivo::Approval.decide!(brief, approver: @approver, decision: "approved")
    brief.send_to!([ @brand.store.id ])
    assert brief.reload.sent?
    assert_equal 1, brief.deliveries.count
  end

  test "compose with send submits for review instead of sending" do
    sign_in(@author)
    assert_difference -> { @tenant.communications.count }, 1 do
      post communications_path, params: {
        commit: "send", org_unit_ids: [ @brand.store.id ],
        communication: { title_fr: "Promo", body_fr: "Texte", format: "news" }
      }
    end
    brief = @tenant.communications.order(:id).last
    assert_redirected_to edit_communication_path(brief)
    assert brief.draft?
    assert brief.review_pending?
    assert_equal 0, brief.deliveries.count
    assert_equal %w[submitted], brief.approval_events.pluck(:kind)
  end

  test "send_brief endpoint cannot bypass the gate" do
    brief = draft_brief
    sign_in(@author)

    post send_brief_communication_path(brief), params: { org_unit_ids: [ @brand.store.id ] }
    assert brief.reload.draft?
    assert brief.review_pending?
    assert_equal 0, brief.deliveries.count

    rejected = draft_brief
    Vazivo::Approval.submit!(rejected, actor: @author)
    Vazivo::Approval.decide!(rejected, approver: @approver, decision: "rejected", note: "Non")
    post send_brief_communication_path(rejected), params: { org_unit_ids: [ @brand.store.id ] }
    assert rejected.reload.draft?
    assert_equal 0, rejected.deliveries.count
  end

  test "approved brief is sent by the author through the controller" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)
    Vazivo::Approval.decide!(brief, approver: @approver, decision: "approved", note: "OK")

    sign_in(@author)
    post send_brief_communication_path(brief), params: { org_unit_ids: [ @brand.store.id ] }
    assert_redirected_to communication_path(brief)
    assert brief.reload.sent?
  end

  test "editing after approval requires a new approval" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)
    Vazivo::Approval.decide!(brief, approver: @approver, decision: "approved")

    sign_in(@author)
    patch communication_path(brief), params: { communication: { body_fr: "Texte modifie" } }
    brief.reload
    assert_nil brief.review_status
    assert_raises(Vazivo::Approval::Required) { brief.send_to!([ @brand.store.id ]) }
  end

  test "recurring occurrences of an approved task are not blocked" do
    task = @tenant.communications.create!(author: @author, title_fr: "Tache", body_fr: "x", format: "task",
                                          status: "draft")
    Vazivo::Approval.submit!(task, actor: @author)
    Vazivo::Approval.decide!(task, approver: @approver, decision: "approved")
    occurrence = @tenant.communications.create!(author: @author, title_fr: "Tache", body_fr: "x", format: "task",
                                                status: "draft", recurrence_parent: task, occurrence_on: Date.current)
    occurrence.send_to!([ @brand.store.id ])
    assert occurrence.reload.sent?
  end

  # -- approve / reject ----------------------------------------------------

  test "another approver approves with a note and the audit trail records it" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)

    sign_in(@approver)
    post approve_communication_path(brief), params: { review_note: "Bon pour envoi" }
    assert_redirected_to edit_communication_path(brief)

    brief.reload
    assert brief.review_approved?
    assert_equal @approver, brief.reviewed_by
    assert_equal "Bon pour envoi", brief.review_note
    assert brief.reviewed_at.present?
    assert_equal %w[submitted approved], brief.approval_events.order(:id).pluck(:kind)
    assert_equal [ @author.id, @approver.id ], brief.approval_events.order(:id).pluck(:actor_id)
    assert_equal "Bon pour envoi", brief.approval_events.find_by(kind: "approved").note
  end

  test "rejection needs a note and keeps sending blocked" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)

    sign_in(@approver)
    post reject_communication_path(brief), params: { review_note: "  " }
    assert brief.reload.review_pending?

    post reject_communication_path(brief), params: { review_note: "Visuel manquant" }
    brief.reload
    assert brief.review_rejected?
    assert_equal "Visuel manquant", brief.review_note
    assert_raises(Vazivo::Approval::Required) { brief.send_to!([ @brand.store.id ]) }
  end

  test "author is notified of the decision" do
    @author.push_subscriptions.create!(tenant: @tenant, endpoint: "https://push.example.test/author",
                                       p256dh: "p256", auth: "auth")
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)

    with_vapid do
      WebPush.stub(:payload_send, true) do
        assert_difference -> { NotificationLog.where(user: @author, notifiable: brief).count }, 1 do
          Vazivo::Approval.decide!(brief, approver: @approver, decision: "rejected", note: "Non")
        end
      end
    end
    log = NotificationLog.where(user: @author, notifiable: brief).last
    assert_equal "web_push", log.channel
    assert_includes log.message, I18n.t("approval.push.rejected", locale: @author.locale)
  end

  # -- permissions ---------------------------------------------------------

  test "author cannot approve their own brief" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)

    sign_in(@author)
    post approve_communication_path(brief), params: { review_note: "Moi" }
    assert_redirected_to edit_communication_path(brief)
    assert_equal I18n.t("approval.errors.self_approval"), flash[:alert]
    assert brief.reload.review_pending?

    assert_raises(Vazivo::Approval::SelfApproval) do
      Vazivo::Approval.decide!(brief, approver: @author, decision: "approved")
    end
    assert_equal %w[submitted], brief.approval_events.pluck(:kind)
  end

  test "area and store users cannot approve or reject" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)

    [ @area_user, @brand.store_user ].each do |user|
      delete logout_path
      sign_in(user)
      post approve_communication_path(brief)
      assert_redirected_to app_root_path
      post reject_communication_path(brief), params: { review_note: "x" }
      assert_redirected_to app_root_path
      assert brief.reload.review_pending?
    end

    assert_raises(Vazivo::Approval::NotAllowed) do
      Vazivo::Approval.decide!(brief, approver: @area_user, decision: "approved")
    end
  end

  test "an approver from another tenant cannot approve" do
    other = build_brand("approval-other", features: { "send_approval" => true })
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)

    sign_in(other.hq)
    post approve_communication_path(brief)
    assert_response :not_found
    assert brief.reload.review_pending?

    assert_raises(Vazivo::Approval::NotAllowed) do
      Vazivo::Approval.decide!(brief, approver: other.hq, decision: "approved")
    end
    assert brief.reload.review_pending?
  end

  test "a decision cannot be repeated once made" do
    brief = draft_brief
    Vazivo::Approval.submit!(brief, actor: @author)
    Vazivo::Approval.decide!(brief, approver: @approver, decision: "approved")

    assert_raises(Vazivo::Approval::NotPending) do
      Vazivo::Approval.decide!(brief, approver: @approver, decision: "rejected", note: "Finalement non")
    end
    assert brief.reload.review_approved?
  end

  # -- playbook deploy -----------------------------------------------------

  def deploy_params(playbook)
    { starts_on: Date.current.iso8601, campaign_on: (Date.current + 7).iso8601,
      brief_fr: "Brief campagne", org_unit_ids: [ @brand.store.id ], key: playbook.key }
  end

  test "playbook deploy waits for approval then deploys" do
    playbook = Playbook.ensure_defaults!(@tenant).first
    sign_in(@author)

    assert_no_difference [ -> { @tenant.checklists.count }, -> { @tenant.communications.count } ] do
      post deploy_playbook_path(playbook), params: deploy_params(playbook)
    end
    assert_redirected_to playbook_deploy_requests_path
    request = @tenant.playbook_deploy_requests.last
    assert request.review_pending?
    assert_equal %w[submitted], request.approval_events.pluck(:kind)

    post approve_playbook_deploy_request_path(request)
    assert_equal I18n.t("approval.errors.self_approval"), flash[:alert]
    assert request.reload.review_pending?
    assert_equal 0, @tenant.checklists.count

    delete logout_path
    sign_in(@approver)
    assert_difference -> { @tenant.checklists.count }, 1 do
      post approve_playbook_deploy_request_path(request), params: { review_note: "Go" }
    end
    request.reload
    assert request.review_approved?
    assert request.deployed?
    assert_equal "sent", request.communication.status
    assert_equal %w[submitted approved deployed], request.approval_events.order(:id).pluck(:kind)

    post approve_playbook_deploy_request_path(request)
    assert_equal 1, @tenant.checklists.count
  end

  test "playbook rejection never deploys" do
    playbook = Playbook.ensure_defaults!(@tenant).first
    request = @tenant.playbook_deploy_requests.create!(
      playbook: playbook, author: @author, deploy_params: deploy_params(playbook).except(:key)
    )
    Vazivo::Approval.submit!(request, actor: @author)

    sign_in(@approver)
    post reject_playbook_deploy_request_path(request), params: { review_note: "Dates fausses" }
    assert request.reload.review_rejected?
    assert_not request.deployed?
    assert_equal 0, @tenant.checklists.count
  end

  test "PlaybookDeployer refuses to deploy without an approved request" do
    playbook = Playbook.ensure_defaults!(@tenant).first
    args = { playbook: playbook, author: @author, campaign_on: Date.current + 7, org_unit_ids: [ @brand.store.id ],
             brief_fr: "Brief" }

    assert_raises(Vazivo::Approval::Required) { Vazivo::PlaybookDeployer.deploy!(**args) }

    pending = @tenant.playbook_deploy_requests.create!(playbook: playbook, author: @author,
                                                       review_status: "pending_review", deploy_params: {})
    assert_raises(Vazivo::Approval::Required) { Vazivo::PlaybookDeployer.deploy!(**args, request: pending) }
    assert_equal 0, @tenant.checklists.count
  end

  test "playbook deploy is unchanged when approval is off" do
    brand = build_brand("approval-off-pb")
    playbook = Playbook.ensure_defaults!(brand.tenant).first
    brief = Vazivo::PlaybookDeployer.deploy!(playbook: playbook, author: brand.hq, campaign_on: Date.current + 7,
                                             org_unit_ids: [ brand.store.id ], brief_fr: "Brief")
    assert brief.sent?
  end

  test "non approvers cannot see or decide playbook requests" do
    playbook = Playbook.ensure_defaults!(@tenant).first
    request = @tenant.playbook_deploy_requests.create!(
      playbook: playbook, author: @author, deploy_params: deploy_params(playbook).except(:key)
    )
    Vazivo::Approval.submit!(request, actor: @author)

    sign_in(@area_user)
    post approve_playbook_deploy_request_path(request)
    assert_redirected_to app_root_path
    assert request.reload.review_pending?
  end
end
