require "test_helper"

class VazivoStoreStatusTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("status-ma")
    @tenant = @brand.tenant
    @agdal = @tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: @brand.region)
    @gueliz = @tenant.org_units.create!(name: "Gueliz", unit_type: "store", parent: @brand.region)
  end

  test "stores without signals are on track" do
    result = Vazivo::StoreStatus.for(@tenant)
    assert_equal({ "on_track" => 3, "attention" => 0, "critical" => 0 }, result.counts)
    assert_equal 3, result.total
  end

  test "overdue work makes a store critical" do
    delivery = send_task("Vitrine", @brand.store)
    delivery.update!(due_at: 1.hour.ago, awareness: "received")

    result = Vazivo::StoreStatus.for(@tenant)
    assert_equal [ @brand.store ], result.stores(:critical)
  end

  test "a redo verdict makes a store critical" do
    delivery = send_task("Vitrine", @agdal)
    delivery.update!(awareness: "received")
    delivery.apply_verdict!("non_conforme", note: "Refaire", by: @brand.hq)

    assert_includes Vazivo::StoreStatus.for(@tenant).stores(:critical), @agdal
  end

  test "unconfirmed or due soon is attention, finished stays on track" do
    soon = send_task("Soon", @gueliz)
    soon.update!(due_at: 1.hour.from_now, awareness: "received")
    done = send_task("Done", @agdal)
    done.update!(status: "completed", completed_at: Time.current, awareness: "done", due_at: 1.hour.ago)

    result = Vazivo::StoreStatus.for(@tenant)
    assert_includes result.stores(:attention), @gueliz
    assert_includes result.stores(:on_track), @agdal
    assert_equal result.counts.values.sum, result.total
  end

  test "buckets are scoped to the tenant" do
    other = build_brand("status-other")
    send_task("Other late", other.store, brand: other).update!(due_at: 1.hour.ago)

    assert_equal 0, Vazivo::StoreStatus.for(@tenant).count(:critical)
    assert_equal 1, Vazivo::StoreStatus.for(other.tenant).count(:critical)
  end

  test "hq board exposes the store status" do
    assert_equal 3, Vazivo::HqBoard.for(@tenant).store_status.total
  end

  private

  def send_task(title, store, brand: @brand)
    brief = brand.tenant.communications.create!(
      author: brand.hq, title_fr: title, body_fr: title, format: "task", status: "draft"
    )
    brief.send_to!([ store.id ])
    brief.deliveries.find_by!(org_unit: store)
  end
end
