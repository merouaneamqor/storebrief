require "test_helper"

class VazivoRegionalCampaignsTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("regional-svc")
    Playbook.ensure_defaults!(@brand.tenant)
    @playbook = @brand.tenant.playbooks.find_by!(key: "sale")
    @other_region = @brand.tenant.org_units.create!(name: "Rabat", unit_type: "region")
    @rabat_store = @brand.tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: @other_region)
    create_user(@brand.tenant, org_unit: @rabat_store, role: :store, email: "agdal@regional-svc.test")
  end

  test "empty tenant has no regional campaign rows" do
    snapshot = Vazivo::RegionalCampaigns.for(@brand.tenant)
    assert_not snapshot.any?
    assert_empty snapshot.regions
    assert_equal 0, snapshot.percent
  end

  test "regions report compliance and store drill-down" do
    checklist = deploy_to([ @brand.store, @rabat_store ])
    casa, rabat = checklist.checklist_deliveries.order(:id).to_a
    casa.update!(status: "completed", completed_at: Time.current)
    rabat.update!(due_at: 2.hours.ago)
    checklist.checklist_items.first(2).each do |item|
      rabat.checklist_item_responses.create!(checklist_item: item, completed: true)
    end

    snapshot = Vazivo::RegionalCampaigns.for(@brand.tenant)
    assert snapshot.any?
    assert_equal 2, snapshot.total
    assert_equal 1, snapshot.done
    assert_equal 1, snapshot.overdue
    assert_equal 50, snapshot.percent

    regions = snapshot.regions.index_by(&:label)
    assert_equal %w[Casa Rabat].sort, regions.keys.sort
    assert_equal 100, regions["Casa"].percent
    assert_equal 0, regions["Casa"].overdue
    assert_equal 0, regions["Rabat"].percent
    assert_equal 1, regions["Rabat"].overdue

    store = regions["Rabat"].stores.sole
    assert_equal "Agdal", store.store_name
    assert_equal 2, store.steps_done
    assert store.overdue
    assert_includes store.path, "store-#{@rabat_store.id}"
    assert_equal @playbook.title, store.campaign_title
  end

  test "regions with overdue stores sort ahead of compliant regions" do
    checklist = deploy_to([ @brand.store, @rabat_store ])
    checklist.checklist_deliveries.find_by!(org_unit: @brand.store)
             .update!(status: "completed", completed_at: Time.current)
    checklist.checklist_deliveries.find_by!(org_unit: @rabat_store)
             .update!(due_at: 1.hour.ago)

    labels = Vazivo::RegionalCampaigns.for(@brand.tenant).regions.map(&:label)
    assert_equal %w[Rabat Casa], labels
  end

  test "plain checklists without a playbook are ignored" do
    checklist = @brand.tenant.checklists.create!(author: @brand.hq, title_fr: "Ménage", status: "draft")
    checklist.send_to!([ @brand.store.id ])

    assert_empty Vazivo::RegionalCampaigns.for(@brand.tenant).regions
  end

  test "fully completed campaigns drop out of the regional rollup" do
    checklist = deploy_to([ @brand.store, @rabat_store ])
    checklist.checklist_deliveries.update_all(status: "completed")

    assert_not Vazivo::RegionalCampaigns.for(@brand.tenant).any?
  end

  test "regional rollup stays tenant scoped" do
    other = build_brand("regional-other")
    Playbook.ensure_defaults!(other.tenant)
    Vazivo::PlaybookDeployer.deploy!(
      playbook: other.tenant.playbooks.find_by!(key: "sale"),
      author: other.hq,
      starts_on: Date.current,
      campaign_on: Date.current + 7,
      brief_fr: "Other",
      org_unit_ids: [ other.store.id ]
    )
    deploy_to([ @brand.store ])

    snapshot = Vazivo::RegionalCampaigns.for(@brand.tenant)
    assert_equal [ "Casa" ], snapshot.regions.map(&:label)
    assert_equal 1, snapshot.total
  end

  private

  def deploy_to(stores)
    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: @brand.hq,
      starts_on: Date.current - 3,
      campaign_on: Date.current + 4,
      brief_fr: @playbook.description_fr,
      org_unit_ids: stores.map(&:id)
    )
    @brand.tenant.checklists.order(:id).last
  end
end
