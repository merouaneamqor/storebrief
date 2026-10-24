require "test_helper"

class VazivoAuditHistoryTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("audit-history", features: { morocco_ops: true })
    @tenant = @brand.tenant
    @region = @brand.region
    @store = @brand.store
    @other = @tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: @region)
    @rabat = @tenant.org_units.create!(name: "Rabat", unit_type: "region")
    @agdal = @tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: @rabat)

    @visit = @tenant.visits.create!(
      org_unit: @store,
      auditor: @brand.hq,
      created_by: @brand.hq,
      planned_at: 1.day.ago.change(hour: 10)
    )

    seed_audit(@store, title: "Audit Maarif 1", score: 100, verdict: "conforme", visit: @visit, at: 2.days.ago)
    seed_audit(@store, title: "Audit Maarif 2", score: 50, verdict: "improve", at: 1.day.ago)
    seed_audit(@other, title: "Audit Anfa", score: 40, verdict: "non_conforme", at: 12.hours.ago)
    seed_audit(@agdal, title: "Audit Agdal", score: 90, verdict: "conforme", at: 6.hours.ago)
  end

  test "explicitly empty permitted stores never fall back to tenant audits" do
    result = Vazivo::AuditHistory.for(@tenant, store_ids: [])
    assert_empty result.entries
    assert_empty result.store_rows
    assert_empty result.region_rows
  end

  test "lists store history newest first with visit link" do
    result = Vazivo::AuditHistory.for(@tenant, store: @store)

    assert_equal 2, result.entries.size
    assert_equal "Audit Maarif 2", result.entries.first.title
    assert_equal 50, result.entries.first.score
    assert_equal "improve", result.entries.first.verdict
    assert_equal @visit.id, result.entries.last.visit_id
    assert_equal 1, result.store_rows.size
    assert_equal 75, result.store_rows.first.avg_score
  end

  test "builds region comparison across stores" do
    result = Vazivo::AuditHistory.for(@tenant)

    assert_equal 2, result.region_rows.size
    casa = result.region_rows.find { |row| row.region == @region }
    rabat = result.region_rows.find { |row| row.region == @rabat }
    assert_equal 2, casa.stores
    assert_equal 3, casa.audits
    assert_equal 1, casa.conforme
    assert_equal 1, casa.improve
    assert_equal 1, casa.non_conforme
    assert_equal 90, rabat.avg_score
  end

  test "filters by region and exports csv" do
    result = Vazivo::AuditHistory.for(@tenant, region: @region)
    assert_equal 3, result.entries.size
    assert result.entries.none? { |entry| entry.store == @agdal }

    csv = Vazivo::AuditHistory.csv(result)
    assert_includes csv, "store,region,title,score,verdict"
    assert_includes csv, "Maarif"
    assert_includes csv, "Casa"
    assert_includes csv, "Audit Anfa"
    refute_includes csv, "Agdal"
  end

  test "ignores deliveries without score" do
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Sans score", body_fr: "Corps", format: "task", status: "draft"
    )
    brief.send_to!([ @store.id ])
    delivery = brief.deliveries.first
    delivery.update!(status: "completed", completed_at: Time.current, verdict: "conforme")

    result = Vazivo::AuditHistory.for(@tenant, store: @store)
    assert result.entries.none? { |entry| entry.title == "Sans score" }
  end

  private

  def seed_audit(store, title:, score:, verdict:, visit: nil, at:)
    brief = @tenant.communications.create!(
      author: @brand.hq,
      title_fr: title,
      body_fr: "Corps",
      format: "task",
      status: "draft",
      visit: visit
    )
    brief.communication_questions.create!(
      position: 0, question_type: "single_choice", title_fr: "OK?",
      options: [ { "label_fr" => "Oui", "correct" => true }, { "label_fr" => "Non" } ]
    )
    brief.send_to!([ store.id ])
    delivery = brief.deliveries.first
    delivery.update!(
      status: "completed",
      completed_at: at,
      score: score,
      verdict: verdict,
      validated_at: at,
      validated_by: @brand.hq
    )
    delivery
  end
end
