require "test_helper"

class TimedChecklistTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("timed-radar", features: { morocco_ops: true, checklists: true, offline_checklists: true })
    @template = @brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Ouverture magasin",
      items: [
        { title_fr: "Alarmes désactivées", requires_photo: false },
        { title_fr: "Photo vitrine", requires_photo: true }
      ]
    )
  end

  test "store radar shows today's checklist ordered by due time with inline mark done" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      afternoon = deploy(@template, title: "Facing après-midi", category: "promotions",
                                    due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 15, 0))
      morning = deploy(@template, title: "Ouverture matin",
                                  due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 9, 0))

      sign_in(@brand.store_user)
      get app_root_path
      assert_response :success

      assert_select "#timed-checklist-title", text: I18n.t("morocco.radar.timed_checklist.title", locale: :en)
      assert_select ".timed-checklist__list .timed-checklist__entry", 2
      assert_select ".timed-checklist__entry:first-child .timed-checklist__title", text: /Ouverture matin/
      assert_select ".timed-checklist__entry:last-child .timed-checklist__title", text: /Facing/
      assert_select ".timed-checklist__bucket--opening", minimum: 1
      assert_select ".timed-checklist__bucket--merch", minimum: 1
      assert_select ".timed-checklist__mark", minimum: 1
      assert_select ".timed-checklist__offline", text: I18n.t("morocco.radar.timed_checklist.offline_hint", locale: :en)

      body = response.body
      assert_operator body.index("Ouverture matin"), :<, body.index("Facing")

      alarm = morning.checklist.checklist_items.find_by!(title_fr: "Alarmes désactivées")
      post submit_item_checklists_delivery_path(morning), params: { item_id: alarm.id, notes: "OK" }
      assert_redirected_to checklists_delivery_path(morning)

      get app_root_path
      assert_response :success
      assert_select ".timed-checklist__line.is-done", minimum: 1
      assert_select ".timed-checklist__entry", text: /Facing/, count: 1
      assert afternoon.pending?
    end
  end

  test "timed checklist copy exists in every locale" do
    %i[en fr es ar].each do |locale|
      assert I18n.t("morocco.radar.timed_checklist.title", locale: locale).present?
      Vazivo::TimedChecklist::BUCKETS.each do |bucket|
        assert I18n.t("morocco.radar.timed_checklist.buckets.#{bucket}", locale: locale).present?
      end
    end
  end

  test "radar snapshot exposes timed checklist for store lens only" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      deploy(@template, title: "Ouverture", due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 9, 0))
      snapshot = Vazivo::Radar.for(user: @brand.store_user, tenant: @brand.tenant)
      assert_equal 1, snapshot.timed_checklist.size
      assert_equal "opening", snapshot.timed_checklist.first.bucket
    end
  end

  private

  def deploy(template, title:, due_at:, category: nil)
    tpl = if category && category != template.category
            @brand.tenant.checklist_templates.create!(
              category: category,
              title_fr: title,
              items: template.items
            )
    else
            template
    end
    checklist = Checklist.build_from_template(tpl, author: @brand.hq)
    checklist.title_fr = title
    checklist.status = "sent"
    checklist.save!
    checklist.checklist_deliveries.create!(org_unit: @brand.store, status: "pending", due_at: due_at)
  end
end
