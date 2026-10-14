require "test_helper"

class VazivoTimedChecklistTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("timed-check", features: { morocco_ops: true, checklists: true, offline_checklists: true })
    @opening = @brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Ouverture",
      items: [ { title_fr: "Alarmes", requires_photo: false } ]
    )
    @merch = @brand.tenant.checklist_templates.create!(
      category: "promotions",
      title_fr: "Facing promo",
      items: [ { title_fr: "PLV", requires_photo: false } ]
    )
  end

  test "orders today's checklist deliveries by due time" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      later = send_checklist(@merch, due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 16, 0))
      earlier = send_checklist(@opening, due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 9, 0))

      entries = Vazivo::TimedChecklist.for(store: @brand.store, tenant: @brand.tenant, user: @brand.store_user)

      assert_equal [ earlier.id, later.id ], entries.map(&:delivery_id)
      assert_equal %w[opening merch], entries.map(&:bucket)
      assert entries.first.lines.any?
      assert_equal earlier.id, entries.first.delivery_id
    end
  end

  test "maps playbook checklists to the campaign bucket" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      playbook = @brand.tenant.playbooks.create!(
        key: "aid_timed",
        title_fr: "AID",
        description_fr: "Campagne AID",
        steps: [ { "offset_days" => 0, "title_fr" => "Vitrine", "requires_photo" => false } ]
      )
      checklist = @brand.tenant.checklists.create!(
        author: @brand.hq,
        playbook: playbook,
        title_fr: "Campagne AID",
        status: "sent"
      )
      checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
      delivery = checklist.checklist_deliveries.create!(
        org_unit: @brand.store,
        status: "pending",
        due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 12, 0)
      )

      entries = Vazivo::TimedChecklist.for(store: @brand.store, tenant: @brand.tenant)
      assert_equal [ delivery.id ], entries.map(&:delivery_id)
      assert_equal "campaign", entries.first.bucket
    end
  end

  test "includes completed checklist deliveries finished today" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      delivery = send_checklist(@opening, due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 8, 0))
      delivery.update!(status: "completed", completed_at: Time.current)

      entries = Vazivo::TimedChecklist.for(store: @brand.store, tenant: @brand.tenant)
      assert_equal 1, entries.size
      assert entries.first.completed
      assert entries.first.lines.all?(&:completed)
    end
  end

  test "excludes other stores and future days" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      other = @brand.tenant.org_units.create!(name: "Gueliz", unit_type: "store", parent: @brand.region)
      send_checklist(@opening, store: other, due_at: Vazivo::Schedule::ZONE.local(2026, 10, 7, 9, 0))
      send_checklist(@merch, due_at: Vazivo::Schedule::ZONE.local(2026, 10, 9, 10, 0))

      entries = Vazivo::TimedChecklist.for(store: @brand.store, tenant: @brand.tenant)
      assert_empty entries
    end
  end

  private

  def send_checklist(template, due_at:, store: @brand.store)
    checklist = Checklist.build_from_template(template, author: @brand.hq)
    checklist.status = "sent"
    checklist.save!
    checklist.checklist_deliveries.create!(org_unit: store, status: "pending", due_at: due_at)
  end
end
