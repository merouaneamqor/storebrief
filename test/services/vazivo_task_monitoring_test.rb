require "test_helper"

class VazivoTaskMonitoringTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("task-monitor")
  end

  test "rolls up weekly completion by region" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Tâche", body_fr: "Corps", format: "task", status: "draft"
    )
    brief.send_to!([ @brand.store.id ])
    delivery = brief.deliveries.first
    delivery.complete!

    snapshot = Vazivo::TaskMonitoring.for(@brand.tenant)
    assert_equal 1, snapshot.done
    assert_equal 1, snapshot.total
    assert_equal 100, snapshot.percent
    assert snapshot.regions.any?
  end
end
