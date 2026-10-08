require "test_helper"

class VisitTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("visit-model")
    @other = build_brand("visit-other")
  end

  def build_visit(**attrs)
    @brand.tenant.visits.new(
      org_unit: @brand.store,
      auditor: @brand.hq,
      planned_at: 2.days.from_now,
      **attrs
    )
  end

  test "is valid with a store, an auditor, and a planned time" do
    assert build_visit.valid?
  end

  test "defaults to planned" do
    assert_equal "planned", build_visit.status
  end

  test "requires a planned time" do
    visit = build_visit(planned_at: nil)
    assert_not visit.valid?
    assert visit.errors.key?(:planned_at)
  end

  test "rejects an org unit that is not a store" do
    assert_not build_visit(org_unit: @brand.region).valid?
  end

  test "rejects a store from another tenant" do
    assert_not build_visit(org_unit: @other.store).valid?
  end

  test "rejects an auditor from another tenant" do
    assert_not build_visit(auditor: @other.hq).valid?
  end

  test "rejects a store user as auditor" do
    assert_not build_visit(auditor: @brand.store_user).valid?
  end

  test "cancel records the time and reason" do
    visit = build_visit
    visit.save!
    visit.cancel!(reason: "Store closed")

    assert visit.cancelled?
    assert_equal "Store closed", visit.cancel_reason
    assert_not_nil visit.cancelled_at
  end

  test "cannot cancel twice" do
    visit = build_visit
    visit.save!
    visit.cancel!
    assert_raises(ArgumentError) { visit.cancel! }
  end

  test "auditor candidates are tenant hq and area users only" do
    candidates = Visit.auditor_candidates(@brand.tenant)
    assert_includes candidates, @brand.hq
    assert_not_includes candidates, @brand.store_user
    assert_not_includes candidates, @other.hq
  end
end
