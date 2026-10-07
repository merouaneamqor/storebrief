require "test_helper"

class HqTaskMonitoringTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("hq-monitor", features: { morocco_ops: true })
  end

  test "hq today shows task completion and region drill-down" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Suivi", body_fr: "Corps", format: "task", status: "draft"
    )
    brief.send_to!([ @brand.store.id ])
    brief.deliveries.first.complete!

    sign_in(@brand.hq)
    get app_root_path
    assert_response :success
    assert_select ".hq-task-monitor"
    assert_match I18n.t("morocco.hq.task_monitoring.title", locale: :en), response.body

    region = @brand.tenant.org_units.regions.first
    assert region, "expected a region in test brand"
    get org_units_path(region_id: region.id)
    assert_response :success
    assert_match @brand.store.name, response.body
  end
end
