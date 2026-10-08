require "test_helper"

class CampaignDashboardTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("campaigns-ma")
    @second_store = @brand.tenant.org_units.create!(name: "Gauthier", unit_type: "store", parent: @brand.region)
    create_user(@brand.tenant, org_unit: @second_store, role: :store, email: "second@campaigns-ma.test")
    Playbook.ensure_defaults!(@brand.tenant)
    @playbook = @brand.tenant.playbooks.find_by!(key: "sale")
  end

  test "dashboard lists the live campaign with compliance and a link to late stores" do
    checklist = deploy_campaign
    done, late = checklist.checklist_deliveries.order(:id).to_a
    done.update!(status: "completed", completed_at: Time.current)
    late.update!(due_at: 2.hours.ago)

    sign_in(@brand.hq)
    get campaigns_playbooks_path
    assert_response :success

    assert_select ".cmp-card", count: 1
    assert_select ".cmp-card__percent strong", text: /50/
    assert_match I18n.t("morocco.playbooks.campaigns.stores_done", done: 1, total: 2, locale: :en), response.body
    assert_select "a[href=?]", checklist_path(checklist, anchor: "store-#{late.org_unit_id}")
  end

  test "a fully completed campaign is no longer live" do
    checklist = deploy_campaign
    checklist.checklist_deliveries.update_all(status: "completed")

    sign_in(@brand.hq)
    get campaigns_playbooks_path
    assert_response :success
    assert_select ".cmp-card", count: 0
    assert_match I18n.t("morocco.playbooks.campaigns.empty", locale: :en), response.body
  end

  test "dashboard is scoped to the tenant" do
    other = build_brand("campaigns-other")
    Playbook.ensure_defaults!(other.tenant)
    Vazivo::PlaybookDeployer.deploy!(
      playbook: other.tenant.playbooks.find_by!(key: "sale"),
      author: other.hq,
      campaign_on: Date.current + 7,
      org_unit_ids: [ other.store.id ]
    )

    sign_in(@brand.hq)
    get campaigns_playbooks_path
    assert_select ".cmp-card", count: 0
  end

  test "dashboard requires head office and the morocco ops flag" do
    sign_in(@brand.store_user)
    get campaigns_playbooks_path
    assert_response :redirect

    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    sign_in(@brand.hq)
    get campaigns_playbooks_path
    assert_response :redirect
  end

  test "campaign anchors exist on the checklist page" do
    checklist = deploy_campaign
    sign_in(@brand.hq)
    get checklist_path(checklist)
    assert_select "li#store-#{@brand.store.id}"
  end

  private

  def deploy_campaign
    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: @brand.hq,
      campaign_on: Date.current + 7,
      org_unit_ids: [ @brand.store.id, @second_store.id ]
    )
    @brand.tenant.checklists.order(:id).last
  end
end
