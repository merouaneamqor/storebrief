require "test_helper"

class CorrectiveActionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("corrective-int", features: { morocco_ops: true, briefs: true, checklists: true })
    @brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Audit promo",
      body_fr: "Vérifier la table",
      format: "task",
      status: "draft",
      source: "compose"
    )
    @brief.send_to!([ @brand.store.id ])
    @delivery = @brief.deliveries.first
    @delivery.apply_verdict!("non_conforme", note: "Repositionner", by: @brand.hq)
    @visit = @brand.tenant.visits.create!(
      org_unit: @brand.store,
      auditor: @brand.hq,
      created_by: @brand.hq,
      planned_at: 2.days.from_now.change(hour: 11),
      status: "planned"
    )
  end

  test "hq creates corrective task from audit delivery linked to visit" do
    @brand.tenant.update!(corrective_deadline_days: 4)
    sign_in(@brand.hq)

    get communication_path(@brief)
    assert_response :success
    assert_match I18n.t("morocco.corrective.create", locale: :en), response.body

    assert_difference -> { @brand.tenant.communications.where(source: "corrective").count }, 1 do
      post delivery_corrective_action_path(@delivery), params: { visit_id: @visit.id }
    end

    corrective = @brand.tenant.communications.where(source: "corrective").order(:id).last
    assert_redirected_to communication_path(corrective)
    follow_redirect!
    assert_match I18n.t("morocco.corrective.created", locale: :en), flash[:notice]
    assert_equal @visit.id, corrective.visit_id
    assert_equal @delivery.id, corrective.source_delivery_id
    assert corrective.sent?
    assert_equal @brand.store, corrective.deliveries.first.org_unit

    due = corrective.due_at.in_time_zone(Vazivo::Schedule::ZONE)
    assert_equal (Vazivo::Schedule.now + 4.days).to_date, due.to_date

    get visit_path(@visit)
    assert_response :success
    assert_match corrective.title, response.body
    assert_match I18n.t("morocco.corrective.visit_section", locale: :en), response.body
  end

  test "store user cannot spawn corrective actions" do
    sign_in(@brand.store_user)

    assert_no_difference -> { Communication.where(source: "corrective").count } do
      post delivery_corrective_action_path(@delivery), params: { visit_id: @visit.id }
    end
    assert_redirected_to app_root_path
  end

  test "hq creates corrective from checklist item missing evidence" do
    checklist = @brand.tenant.checklists.create!(
      author: @brand.hq,
      title_fr: "Closing",
      description_fr: "Fin de journée",
      status: "draft"
    )
    item = checklist.checklist_items.create!(
      position: 0,
      title_fr: "Caisse fermée",
      requires_photo: true,
      required: true
    )
    checklist.send_to!([ @brand.store.id ])
    response_record = checklist.checklist_deliveries.first.checklist_item_responses.create!(
      checklist_item: item,
      completed: true
    )

    sign_in(@brand.hq)
    get checklist_path(checklist)
    assert_response :success
    assert_match I18n.t("morocco.corrective.create", locale: :en), response.body

    assert_difference -> { @brand.tenant.communications.where(source: "corrective").count }, 1 do
      post checklist_item_corrective_action_path(response_record), params: { visit_id: @visit.id }
    end

    corrective = @brand.tenant.communications.where(source: "corrective").order(:id).last
    assert_redirected_to communication_path(corrective)
    assert_equal response_record, corrective.source_checklist_item_response
    assert_equal @visit, corrective.visit
  end
end
