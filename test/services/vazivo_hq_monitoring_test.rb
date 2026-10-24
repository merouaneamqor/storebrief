require "test_helper"

class VazivoHqMonitoringTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("hq-monitor")
    @second = @brand.tenant.org_units.create!(name: "Gauthier", unit_type: "store", parent: @brand.region)
    create_user(@brand.tenant, org_unit: @second, role: :store, email: "second@hq-monitor.test")
    @other_region = @brand.tenant.org_units.create!(name: "Rabat", unit_type: "region")
    @rabat_store = @brand.tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: @other_region)
    create_user(@brand.tenant, org_unit: @rabat_store, role: :store, email: "agdal@hq-monitor.test")
  end

  test "task monitoring reports completion percent overdue and campaign groups" do
    brief = send_task("Vitrine Black Friday", stores: [ @brand.store, @second, @rabat_store ])
    done, late, open = brief.deliveries.order(:id).to_a
    done.update!(status: "completed", completed_at: Time.current, awareness: "done")
    late.update!(due_at: 2.hours.ago)
    open.update!(due_at: 2.hours.from_now)

    board = Vazivo::HqBoard.for(@brand.tenant)
    monitoring = board.task_monitoring

    assert monitoring.any?
    assert_equal 3, monitoring.total
    assert_equal 1, monitoring.done
    assert_equal 1, monitoring.overdue
    assert_equal 33, monitoring.percent

    campaign = monitoring.by_campaign.first
    assert_equal "Vitrine Black Friday", campaign.label
    assert_equal 33, campaign.percent
    assert_equal 1, campaign.overdue
    assert_equal 3, campaign.stores.size
    assert campaign.stores.any?(&:overdue)
    assert campaign.stores.any?(&:finished)
  end

  test "task monitoring groups stores by region with drill-down rows" do
    brief = send_task("Planogramme", stores: [ @brand.store, @rabat_store ])
    brief.deliveries.find_by!(org_unit: @brand.store).update!(status: "completed", completed_at: Time.current)
    brief.deliveries.find_by!(org_unit: @rabat_store).update!(due_at: 1.hour.ago)

    monitoring = Vazivo::HqBoard.for(@brand.tenant).task_monitoring
    regions = monitoring.by_region.index_by(&:label)

    assert_equal %w[Casa Rabat].sort, regions.keys.sort
    assert_equal 100, regions["Casa"].percent
    assert_equal 0, regions["Casa"].overdue
    assert_equal 0, regions["Rabat"].percent
    assert_equal 1, regions["Rabat"].overdue
    assert_equal "Agdal", regions["Rabat"].stores.first.store_name
    assert_includes regions["Rabat"].stores.first.path, "store-#{@rabat_store.id}"
  end

  test "fully completed tasks drop out of live monitoring" do
    brief = send_task("Done campaign", stores: [ @brand.store ])
    brief.deliveries.update_all(status: "completed")

    monitoring = Vazivo::HqBoard.for(@brand.tenant).task_monitoring
    assert_not monitoring.any?
    assert_equal 0, monitoring.total
    assert_equal [], monitoring.by_campaign
  end

  test "task monitoring stays tenant scoped" do
    other = build_brand("hq-monitor-other")
    send_task("Other only", stores: [ other.store ], brand: other)
    send_task("Ours open", stores: [ @brand.store ])

    monitoring = Vazivo::HqBoard.for(@brand.tenant).task_monitoring
    assert_equal 1, monitoring.by_campaign.size
    assert_equal "Ours open", monitoring.by_campaign.first.label
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
end
