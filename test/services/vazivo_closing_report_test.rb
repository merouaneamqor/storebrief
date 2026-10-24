require "test_helper"

class VazivoClosingReportTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("closing-svc")
    @second = @brand.tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: @brand.region)
    create_user(@brand.tenant, org_unit: @second, role: :store, email: "anfa@closing-svc.test")
    Playbook.ensure_defaults!(@brand.tenant)
    @playbook = @brand.tenant.playbooks.find_by!(key: "aid")
  end

  test "empty tenant has no closed reports" do
    snapshot = Vazivo::ClosingReport.closed_for(@brand.tenant)
    assert_empty snapshot.reports
    assert_equal 0, snapshot.total
  end

  test "live campaign is not closed until stores finish or campaign day passes" do
    checklist = deploy!(campaign_on: Date.current + 5)
    snapshot = Vazivo::ClosingReport.closed_for(@brand.tenant)
    assert_empty snapshot.reports

    report = Vazivo::ClosingReport.for(@brand.tenant, checklist: checklist)
    assert_not report.closed
    assert_equal 2, report.total
    assert_equal 0, report.done
  end

  test "completed campaign reports metrics and top bottom stores" do
    checklist = deploy!(campaign_on: Date.current - 1)
    top, bottom = checklist.checklist_deliveries.order(:id).to_a
    top.update!(status: "completed", completed_at: 2.days.ago, due_at: 1.day.ago)
    checklist.checklist_items.first(5).each do |item|
      top.checklist_item_responses.create!(checklist_item: item, completed: true)
    end
    bottom.update!(status: "completed", completed_at: Time.current, due_at: 2.days.ago)
    checklist.checklist_items.first(1).each do |item|
      bottom.checklist_item_responses.create!(checklist_item: item, completed: true)
    end

    report = Vazivo::ClosingReport.for(@brand.tenant, checklist: checklist)
    assert report.closed
    assert_equal 100, report.percent
    assert_equal 2, report.done
    assert_equal 1, report.on_time
    assert_equal 1, report.overdue
    assert_equal top.org_unit.name, report.top_stores.first.store_name
    assert_equal bottom.org_unit.name, report.bottom_stores.first.store_name

    snapshot = Vazivo::ClosingReport.closed_for(@brand.tenant)
    assert_equal 1, snapshot.total
    assert_equal checklist, snapshot.reports.sole.checklist
  end

  test "rejects checklists from another tenant" do
    other = build_brand("closing-other")
    Playbook.ensure_defaults!(other.tenant)
    Vazivo::PlaybookDeployer.deploy!(
      playbook: other.tenant.playbooks.find_by!(key: "aid"),
      author: other.hq,
      starts_on: Date.current - 7,
      campaign_on: Date.current - 1,
      brief_fr: "Other",
      org_unit_ids: [ other.store.id ]
    )
    foreign = other.tenant.checklists.order(:id).last

    assert_raises(ArgumentError) do
      Vazivo::ClosingReport.for(@brand.tenant, checklist: foreign)
    end
  end

  private

  def deploy!(campaign_on:)
    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: @brand.hq,
      starts_on: campaign_on - 7,
      campaign_on: campaign_on,
      brief_fr: @playbook.description_fr,
      org_unit_ids: [ @brand.store.id, @second.id ]
    )
    @brand.tenant.checklists.order(:id).last
  end
end
