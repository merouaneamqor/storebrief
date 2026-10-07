require "test_helper"

class VazivoCampaignDashboardTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("campaign-svc")
    Playbook.ensure_defaults!(@brand.tenant)
    @playbook = @brand.tenant.playbooks.find_by!(key: "aid")
  end

  test "empty tenant has no campaigns and zero compliance" do
    snapshot = Vazivo::CampaignDashboard.for(@brand.tenant)
    assert_empty snapshot.campaigns
    assert_equal 0, snapshot.percent
  end

  test "a plain checklist without a playbook is not a campaign" do
    checklist = @brand.tenant.checklists.create!(author: @brand.hq, title_fr: "Ménage", status: "draft")
    checklist.send_to!([ @brand.store.id ])

    assert_empty Vazivo::CampaignDashboard.for(@brand.tenant).campaigns
  end

  test "campaign reports completion, late stores and step progress" do
    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook, author: @brand.hq, campaign_on: Date.current + 3, org_unit_ids: [ @brand.store.id ]
    )
    checklist = @brand.tenant.checklists.order(:id).last
    delivery = checklist.checklist_deliveries.first
    delivery.update!(due_at: 1.hour.ago)
    checklist.checklist_items.first(2).each do |item|
      delivery.checklist_item_responses.create!(checklist_item: item, completed: true)
    end

    snapshot = Vazivo::CampaignDashboard.for(@brand.tenant)
    campaign = snapshot.campaigns.sole
    assert_equal checklist, campaign.checklist
    assert_equal 0, campaign.percent
    assert_equal 1, campaign.pending
    assert_equal 1, snapshot.exception_count

    row = campaign.exceptions.sole
    assert_equal @brand.store.name, row.store_name
    assert_equal 2, row.steps_done
    assert_equal 7, row.steps_total
    assert_equal "late", row.tone
  end
end
