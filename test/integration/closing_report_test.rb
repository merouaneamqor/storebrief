require "test_helper"

class ClosingReportTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("closing-ma")
    @second_store = @brand.tenant.org_units.create!(name: "Gauthier", unit_type: "store", parent: @brand.region)
    create_user(@brand.tenant, org_unit: @second_store, role: :store, email: "second@closing-ma.test")
    Playbook.ensure_defaults!(@brand.tenant)
    @playbook = @brand.tenant.playbooks.find_by!(key: "sale")
  end

  test "hq sees closed campaign summary top bottom stores and html export" do
    checklist = deploy_and_close!

    sign_in(@brand.hq)
    get closing_reports_playbooks_path
    assert_response :success
    assert_match I18n.t("morocco.playbooks.closing.title", locale: :en), response.body
    assert_select "a[href=?]", closing_report_playbooks_path(checklist)

    get closing_report_playbooks_path(checklist)
    assert_response :success
    assert_match I18n.t("morocco.playbooks.closing.report_title", title: checklist.playbook.title, locale: :en), response.body
    assert_match I18n.t("morocco.playbooks.closing.top_stores", locale: :en), response.body
    assert_match I18n.t("morocco.playbooks.closing.bottom_stores", locale: :en), response.body
    assert_select ".clos-summary"
    assert_select "a[href=?]", closing_report_playbooks_path(checklist, export: 1)

    get closing_report_playbooks_path(checklist, export: 1)
    assert_response :success
    assert_select "body.export-body"
    assert_match I18n.t("morocco.playbooks.closing.print", locale: :en), response.body
    assert_select ".app-sidebar", count: 0
  end

  test "closing reports are tenant scoped" do
    other = build_brand("closing-other")
    Playbook.ensure_defaults!(other.tenant)
    Vazivo::PlaybookDeployer.deploy!(
      playbook: other.tenant.playbooks.find_by!(key: "sale"),
      author: other.hq,
      starts_on: Date.current - 10,
      campaign_on: Date.current - 2,
      brief_fr: "Other brief",
      org_unit_ids: [ other.store.id ]
    )
    foreign = other.tenant.checklists.order(:id).last
    foreign.checklist_deliveries.update_all(status: "completed", completed_at: Time.current)

    sign_in(@brand.hq)
    get closing_reports_playbooks_path
    assert_select ".cmp-card", count: 0

    get closing_report_playbooks_path(foreign)
    assert_response :not_found
  end

  test "closing reports require head office and morocco ops" do
    checklist = deploy_and_close!

    sign_in(@brand.store_user)
    get closing_reports_playbooks_path
    assert_response :redirect
    get closing_report_playbooks_path(checklist)
    assert_response :redirect

    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    sign_in(@brand.hq)
    get closing_reports_playbooks_path
    assert_response :redirect
  end

  private

  def deploy_and_close!
    campaign_on = Date.current - 2
    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: @brand.hq,
      starts_on: campaign_on - 7,
      campaign_on: campaign_on,
      brief_fr: @playbook.description_fr,
      org_unit_ids: [ @brand.store.id, @second_store.id ]
    )
    checklist = @brand.tenant.checklists.order(:id).last
    done, late = checklist.checklist_deliveries.order(:id).to_a
    done.update!(status: "completed", completed_at: campaign_on.in_time_zone - 1.day, due_at: campaign_on.in_time_zone)
    checklist.checklist_items.first(4).each do |item|
      done.checklist_item_responses.create!(checklist_item: item, completed: true)
    end
    late.update!(status: "completed", completed_at: Time.current, due_at: campaign_on.in_time_zone)
    checklist.checklist_items.first(1).each do |item|
      late.checklist_item_responses.create!(checklist_item: item, completed: true)
    end
    checklist
  end
end
