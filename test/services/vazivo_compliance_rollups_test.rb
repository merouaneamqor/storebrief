require "test_helper"

class VazivoComplianceRollupsTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("hq-rollups")
    Playbook.ensure_defaults!(@brand.tenant)
  end

  test "empty modules and missing products show nil percent not zero" do
    rollups = Vazivo::HqBoard.for(@brand.tenant).compliance_rollups

    assert_equal %w[tasks audits campaigns training vm], rollups.modules.map(&:key)
    assert_nil rollups["tasks"].percent
    assert_equal "-", rollups["tasks"].display_percent
    assert_nil rollups["audits"].percent
    assert_nil rollups["campaigns"].percent
    assert_nil rollups["training"].percent
    assert_equal false, rollups["training"].available
    assert_nil rollups["vm"].percent
    assert_equal false, rollups["vm"].available
    assert_equal "-", rollups["training"].display_percent
    assert_equal "-", rollups["vm"].display_percent
  end

  test "tasks rollup reports week completion percent" do
    second = @brand.tenant.org_units.create!(name: "Gauthier", unit_type: "store", parent: @brand.region)
    create_user(@brand.tenant, org_unit: second, role: :store, email: "gauthier@hq-rollups.test")
    brief = send_task("Vitrine", stores: [ @brand.store, second ])
    brief.deliveries.find_by!(org_unit: @brand.store).update!(status: "completed", completed_at: Time.current)

    tasks = Vazivo::HqBoard.for(@brand.tenant).compliance_rollups["tasks"]
    assert tasks.available
    assert_equal 2, tasks.total
    assert_equal 1, tasks.done
    assert_equal 50, tasks.percent
    assert_equal "50%", tasks.display_percent
  end

  test "audits rollup averages scored deliveries this week" do
    seed_audit(score: 100, verdict: "conforme")
    seed_audit(score: 50, verdict: "improve")

    audits = Vazivo::HqBoard.for(@brand.tenant).compliance_rollups["audits"]
    assert audits.available
    assert_equal 75, audits.percent
    assert_equal 2, audits.total
    assert_includes audits.path, "audit_history"
  end

  test "campaigns rollup uses live playbook campaign completion" do
    playbook = @brand.tenant.playbooks.find_by!(key: "aid")
    Vazivo::PlaybookDeployer.deploy!(
      playbook: playbook,
      author: @brand.hq,
      starts_on: Date.current - 11,
      campaign_on: Date.current + 3,
      brief_fr: playbook.description_fr,
      org_unit_ids: [ @brand.store.id ]
    )

    dashboard = Vazivo::CampaignDashboard.for(@brand.tenant)
    assert dashboard.total.positive?

    campaigns = Vazivo::HqBoard.for(@brand.tenant).compliance_rollups["campaigns"]
    assert campaigns.available
    assert_equal dashboard.total, campaigns.total
    assert_equal dashboard.done, campaigns.done
    assert_equal dashboard.percent, campaigns.percent
    assert_includes campaigns.path, "campaigns"
  end

  test "compliance rollups stay tenant scoped" do
    other = build_brand("hq-rollups-other")
    send_task("Other only", stores: [ other.store ], brand: other)
    other.tenant.communications.sent.first.deliveries.update_all(status: "completed", completed_at: Time.current)

    send_task("Ours open", stores: [ @brand.store ])

    ours = Vazivo::HqBoard.for(@brand.tenant).compliance_rollups["tasks"]
    assert_equal 1, ours.total
    assert_equal 0, ours.done
    assert_equal 0, ours.percent
  end

  private

  def send_task(title, stores:, brand: @brand)
    brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: title,
      body_fr: title,
      format: "task",
      status: "draft"
    ).tap { |brief| brief.send_to!(stores.map(&:id)) }
  end

  def seed_audit(score:, verdict:)
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Audit #{score}",
      body_fr: "Corps",
      format: "task",
      status: "draft"
    )
    brief.communication_questions.create!(
      position: 0, question_type: "single_choice", title_fr: "OK?",
      options: [ { "label_fr" => "Oui", "correct" => true }, { "label_fr" => "Non" } ]
    )
    brief.send_to!([ @brand.store.id ])
    brief.deliveries.first.update!(
      status: "completed",
      completed_at: Time.current,
      score: score,
      verdict: verdict,
      validated_at: Time.current,
      validated_by: @brand.hq
    )
  end
end
