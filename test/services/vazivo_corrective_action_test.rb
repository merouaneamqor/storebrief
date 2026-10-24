require "test_helper"

class VazivoCorrectiveActionTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("corrective-svc", features: { morocco_ops: true })
    @tenant = @brand.tenant
    @brief = @tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Audit rayon",
      body_fr: "Contrôle facing",
      format: "task",
      status: "draft",
      source: "compose"
    )
    @brief.send_to!([ @brand.store.id ])
    @delivery = @brief.deliveries.first
    @delivery.apply_verdict!("non_conforme", note: "Refaire le facing", by: @brand.hq)
    @visit = @tenant.visits.create!(
      org_unit: @brand.store,
      auditor: @brand.hq,
      created_by: @brand.hq,
      planned_at: 1.day.from_now.change(hour: 10),
      status: "planned"
    )
  end

  test "spawns a sent task linked to delivery and visit with tenant deadline" do
    @tenant.update!(corrective_deadline_days: 5)

    brief = nil
    assert_difference -> { Communication.where(source: "corrective").count }, 1 do
      brief = Vazivo::CorrectiveAction.spawn_from_delivery!(
        delivery: @delivery,
        author: @brand.hq,
        visit: @visit
      )
    end

    assert brief.sent?
    assert brief.task?
    assert brief.requires_proof?
    assert_equal "important", brief.priority
    assert_equal @visit, brief.visit
    assert_equal @delivery, brief.source_delivery
    assert_equal @brand.store, brief.deliveries.first.org_unit
    assert_includes brief.title_fr, "Audit rayon"
    assert_includes brief.body_fr, "Refaire le facing"

    due = brief.due_at.in_time_zone(Vazivo::Schedule::ZONE)
    expected_day = (Vazivo::Schedule.now + 5.days).to_date
    assert_equal expected_day, due.to_date
  end

  test "rejects conforme verdicts and duplicate spawn" do
    @delivery.apply_verdict!("conforme", note: "OK", by: @brand.hq)
    assert_raises(Vazivo::CorrectiveAction::Error) do
      Vazivo::CorrectiveAction.spawn_from_delivery!(delivery: @delivery, author: @brand.hq)
    end

    @delivery.apply_verdict!("improve", note: "Ajuster", by: @brand.hq)
    Vazivo::CorrectiveAction.spawn_from_delivery!(delivery: @delivery, author: @brand.hq)
    assert_raises(Vazivo::CorrectiveAction::Error) do
      Vazivo::CorrectiveAction.spawn_from_delivery!(delivery: @delivery, author: @brand.hq)
    end
  end

  test "spawns from checklist item missing evidence" do
    checklist = @tenant.checklists.create!(
      author: @brand.hq,
      title_fr: "Ouverture",
      description_fr: "Contrôle",
      status: "draft"
    )
    item = checklist.checklist_items.create!(
      position: 0,
      title_fr: "Vitrine propre",
      requires_photo: true,
      required: true
    )
    checklist.send_to!([ @brand.store.id ])
    checklist_delivery = checklist.checklist_deliveries.first
    response = checklist_delivery.checklist_item_responses.create!(
      checklist_item: item,
      completed: false,
      notes: "Pas encore fait"
    )

    brief = Vazivo::CorrectiveAction.spawn_from_checklist_item!(
      response: response,
      author: @brand.hq,
      visit: @visit
    )

    assert brief.corrective?
    assert_equal response, brief.source_checklist_item_response
    assert_equal @visit, brief.visit
    assert_includes brief.body_fr, "Pas encore fait"
  end

  test "default deadline days fall back to three" do
    assert_equal 3, Vazivo::CorrectiveAction.normalize_deadline_days(nil)
    assert_equal 3, Vazivo::CorrectiveAction.normalize_deadline_days(0)
    assert_equal 7, Vazivo::CorrectiveAction.normalize_deadline_days(7)
  end
end
