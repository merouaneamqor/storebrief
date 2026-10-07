require "test_helper"

class VazivoMoroccoTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("vazivo-ma")
  end

  test "hq can send a task with an owner and a deadline" do
    sign_in(@brand.hq)

    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Mettez la vitrine comme ça.",
      title_ar: "تركيب الواجهة",
      body_fr: "Photo avant et après.",
      format: "task",
      status: "draft",
      source: "compose",
      requires_proof: true,
      due_at: Time.find_zone("Africa/Casablanca").local(2026, 10, 6, 18, 0)
    )
    brief.send_to!([ @brand.store.id ])

    delivery = brief.deliveries.find_by!(org_unit: @brand.store)
    assert_equal @brand.store_user, delivery.assignee
    assert_equal 18, delivery.due_at.in_time_zone("Africa/Casablanca").hour
    assert_equal "pending", delivery.awareness
    assert brief.requires_proof?
  end

  test "the store confirms receipt in order and closes with before and after photos" do
    brief = task_for(@brand, proof: true)
    delivery = brief.deliveries.first
    sign_in(@brand.store_user)

    %w[received read understood in_progress].each do |step|
      post advance_inbox_path(delivery), params: { step: step }
      assert_redirected_to inbox_path(delivery)
      assert_equal step, delivery.reload.awareness
    end

    post advance_inbox_path(delivery), params: { step: "done" }
    assert_equal "in_progress", delivery.reload.awareness
    follow_redirect!
    assert_match I18n.t("morocco.proof_required", locale: :en), response.body

    photo = fixture_file_upload("window.jpg", "image/jpeg")
    post advance_inbox_path(delivery), params: { step: "done", photo_before: photo, photo_after: photo }
    assert_equal "done", delivery.reload.awareness
    assert_equal "completed", delivery.status
    assert delivery.photo_before.attached?
    assert delivery.photo_after.attached?
  end

  test "head office sees who received the brief and can coach the store" do
    brief = task_for(@brand, proof: false)
    delivery = brief.deliveries.first
    sign_in(@brand.store_user)
    post advance_inbox_path(delivery), params: { step: "received" }

    sign_in(@brand.hq)
    get communication_path(brief)
    assert_response :success
    assert_match I18n.t("morocco.hq.received_line", done: 1, total: 1, locale: :en), response.body
    assert_match I18n.t("communications.stores", locale: :en), response.body

    post delivery_verdict_path(delivery), params: { verdict: "conforme", verdict_note: "Belle vitrine." }
    assert_redirected_to communication_path(brief)
    assert_equal "conforme", delivery.reload.verdict
    assert_equal "Belle vitrine.", delivery.verdict_note
  end

  test "head office today is an exception board" do
    task_for(@brand, proof: false)
    sign_in(@brand.hq)

    get app_root_path
    assert_response :success
    assert_match I18n.t("morocco.hq.today_title", locale: :en), response.body
    assert_match I18n.t("morocco.hq.board_unconfirmed", locale: :en), response.body
    assert_match I18n.t("morocco.hq.board_overdue", locale: :en), response.body
    assert_match I18n.t("morocco.hq.exceptions", locale: :en), response.body
    assert_select ".exception-list"
    assert_select ".hq-pulse__tile"
    assert_select ".hq-hero"
    assert_match I18n.t("communications.notify_push", locale: :en), response.body
    assert_select "form[action=?]", notify_push_communication_path(@brand.tenant.communications.sent.last)
  end

  test "a playbook deploys the same campaign to the store" do
    Playbook.ensure_defaults!(@brand.tenant)
    playbook = @brand.tenant.playbooks.find_by!(key: "aid")
    sign_in(@brand.hq)

    assert_difference -> { @brand.tenant.checklists.count }, 1 do
      post deploy_playbook_path(playbook), params: {
        campaign_on: Date.new(2026, 6, 16).iso8601,
        org_unit_ids: [ @brand.store.id ]
      }
    end

    assert_redirected_to playbooks_path(key: playbook.key)
    checklist = @brand.tenant.checklists.order(:id).last
    assert_equal playbook, checklist.playbook
    assert_equal "sent", checklist.status
    assert_equal 7, checklist.checklist_items.count
    assert_equal @brand.store_user, checklist.checklist_deliveries.first.assignee

    confirmation = @brand.tenant.communications.where(source: "playbook").order(:id).last
    assert_equal "pending", confirmation.deliveries.first.awareness
  end

  test "playbook targets preview resolves stores under a region within the tenant" do
    Playbook.ensure_defaults!(@brand.tenant)
    playbook = @brand.tenant.playbooks.find_by!(key: "aid")
    other = build_brand("vazivo-other")
    sign_in(@brand.hq)

    get preview_playbook_path(playbook, format: :json), params: { org_unit_ids: [ @brand.region.id, other.store.id ] }

    assert_response :success
    body = response.parsed_body
    assert_equal 1, body["count"]
    assert_equal [ @brand.store.id ], body["stores"].map { |store| store["id"] }
    assert_equal "Casa", body["stores"].first["region"]

    get preview_playbook_path(playbook, format: :json)
    assert_equal 0, response.parsed_body["count"]
  end

  test "deploying a playbook persists the target snapshot and requires targets" do
    Playbook.ensure_defaults!(@brand.tenant)
    playbook = @brand.tenant.playbooks.find_by!(key: "aid")
    sign_in(@brand.hq)

    assert_no_difference -> { @brand.tenant.checklists.count } do
      post deploy_playbook_path(playbook), params: { campaign_on: Date.new(2026, 6, 16).iso8601 }
    end
    assert_redirected_to playbooks_path(key: playbook.key)

    post deploy_playbook_path(playbook), params: {
      campaign_on: Date.new(2026, 6, 16).iso8601,
      org_unit_ids: [ @brand.region.id ]
    }

    snapshot = @brand.tenant.checklists.order(:id).last.target_snapshot
    assert_equal 1, snapshot["store_count"]
    assert_equal [ @brand.store.id ], snapshot["stores"].map { |store| store["id"] }
    assert_equal [ @brand.region.id ], snapshot["selection"].map { |unit| unit["id"] }
    assert snapshot["captured_at"].present?
  end

  test "playbooks page lets hq pick targets from the org tree" do
    sign_in(@brand.hq)

    get playbooks_path

    assert_response :success
    assert_select "input[type=checkbox][name='org_unit_ids[]'][value='#{@brand.region.id}']"
    assert_select "input[type=checkbox][name='org_unit_ids[]'][value='#{@brand.store.id}']"
    assert_select "form.pb-deploy[x-data=campaignTargets]"
  end

  test "hq can customize and create playbooks" do
    Playbook.ensure_defaults!(@brand.tenant)
    playbook = @brand.tenant.playbooks.find_by!(key: "sale")
    sign_in(@brand.hq)

    patch playbook_path(playbook), params: {
      playbook: {
        title_fr: "Soldes maison",
        title_ar: "تخفيضات البيت",
        description_fr: "Séquence maison.",
        description_ar: "تسلسل داخلي.",
        steps: [
          { offset_days: -2, title_fr: "Prix vitrine", title_ar: "أسعار الواجهة", requires_photo: "1" },
          { offset_days: 0, title_fr: "Photo J", title_ar: "صورة اليوم", requires_photo: "0" }
        ]
      }
    }
    assert_redirected_to playbooks_path(key: "sale")
    playbook.reload
    assert_equal "Soldes maison", playbook.title_fr
    assert_equal 2, playbook.step_list.size
    assert_equal "Prix vitrine", playbook.step_list.first[:title_fr]
    assert playbook.step_list.first[:requires_photo]

    assert_difference -> { @brand.tenant.playbooks.count }, 1 do
      post playbooks_path, params: {
        playbook: {
          title_fr: "Ramadan ouverture",
          title_ar: "افتتاح رمضان",
          description_fr: "Préparation magasin pour l'ouverture Ramadan.",
          description_ar: "تحضير المتجر لافتتاح رمضان.",
          steps: [
            { offset_days: -5, title_fr: "Stock dates", requires_photo: "0" },
            { offset_days: 0, title_fr: "Vitrine Ramadan", requires_photo: "1" }
          ]
        }
      }
    end
    custom = @brand.tenant.playbooks.order(:id).last
    assert custom.custom?
    assert_equal "ramadan_ouverture", custom.key
    assert_redirected_to playbooks_path(key: custom.key)

    # ensure_defaults must not wipe custom edits
    Playbook.ensure_defaults!(@brand.tenant)
    assert_equal "Soldes maison", playbook.reload.title_fr
    assert_equal 2, playbook.step_list.size
  end

  test "the store morning screen is the radar" do
    task_for(@brand, proof: false)
    sign_in(@brand.store_user)

    get app_root_path
    assert_response :success
    assert_match I18n.t("morocco.radar.place_store", locale: :en), response.body
    assert_match I18n.t("morocco.radar.now", locale: :en), response.body
    assert_match "Contrôle vitrine", response.body
    assert_select "article.work-card.work-card--hero"
    assert_select ".work-card--hero .btn", minimum: 1
  end

  test "the store later section stays collapsed" do
    brief = task_for(@brand, proof: false)
    delivery = brief.deliveries.first
    delivery.update!(due_at: 2.days.from_now)
    sign_in(@brand.store_user)

    get app_root_path
    assert_response :success
    assert_select "details.later-fold:not([open])"
  end

  test "the store task page has one next action and no second complete button" do
    brief = task_for(@brand, proof: false)
    delivery = brief.deliveries.first
    sign_in(@brand.store_user)

    get inbox_path(delivery)
    assert_response :success
    assert_select "article.task-card"
    assert_select "ol.stepper"
    assert_select "button", text: I18n.t("morocco.awareness.actions.received", locale: :en)
    assert_select "button", text: I18n.t("inbox.mark_complete", locale: :en), count: 0
  end

  private

  def task_for(brand, proof:)
    brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Contrôle vitrine",
      title_ar: "فحص الواجهة",
      body_fr: "Mettez la vitrine comme ça.",
      body_ar: "يرجى تركيب الواجهة وفق النموذج المرفق.",
      format: "task",
      status: "draft",
      source: "compose",
      requires_proof: proof
    ).tap { |brief| brief.send_to!([ brand.store.id ]) }
  end
end
