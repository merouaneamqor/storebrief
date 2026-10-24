require "test_helper"

class ReportSubscriptionTest < ActiveSupport::TestCase
  test "subscriptions require explicit opt-in and schedule weekly or monthly in Morocco time" do
    brand = build_brand("subscription-model")
    subscription = ReportSubscription.new(tenant: brand.tenant, user: brand.hq)
    assert_not subscription.enabled?
    subscription.save!
    assert_nil subscription.next_delivery_at
    now = Time.find_zone!(Vazivo::Schedule::ZONE).local(2026, 3, 9, 7)
    travel_to(now) do
      subscription.update!(enabled: true)
      assert_equal Time.find_zone!(Vazivo::Schedule::ZONE).local(2026, 3, 9, 8), subscription.next_delivery_at
      assert_equal Date.new(2026, 3, 2)..Date.new(2026, 3, 8), subscription.reporting_period(now).dates
      subscription.update!(frequency: "monthly")
      assert_equal Date.new(2026, 4, 1), subscription.next_delivery_at.in_time_zone(Vazivo::Schedule::ZONE).to_date
      assert_equal Date.new(2026, 2, 1)..Date.new(2026, 2, 28), subscription.reporting_period(now).dates
      subscription.update!(enabled: false)
      assert_nil subscription.next_delivery_at
    end
    foreign = build_brand("foreign-subscription")
    subscription.user = foreign.hq
    assert_not subscription.valid?
    assert subscription.errors.of_kind?(:user, :invalid)
  end
end
