require "test_helper"

class ReportSubscriptionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("subscription-ui")
  end

  test "report subscriptions are opt in, translated and controlled only by the current user" do
    sign_in(@brand.hq)
    %w[fr ar en es].each do |locale|
      get report_subscription_path, params: { locale: locale }
      assert_response :success
      assert_select "input[name='report_subscription[enabled]'][checked]", count: 0
      assert_select "input[name='report_subscription[csv_attachment]']"
      assert_no_match "translation missing", response.body
    end
    assert_no_difference "ReportSubscription.count" do
      get report_subscription_path
    end
    patch report_subscription_path, params: { report_subscription: { enabled: "1", frequency: "monthly", csv_attachment: "1", user_id: @brand.store_user.id } }
    assert_redirected_to report_subscription_path
    subscription = @brand.hq.reload.report_subscription
    assert subscription.enabled?
    assert subscription.csv_attachment?
    assert_equal "monthly", subscription.frequency
    assert_equal @brand.tenant.id, subscription.tenant_id
    assert_nil @brand.store_user.reload.report_subscription
    patch report_subscription_path, params: { report_subscription: { enabled: "0" } }
    assert_not subscription.reload.enabled?
    assert_nil subscription.next_delivery_at
  end

  test "area can subscribe but stores and disabled features cannot" do
    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    sign_in(area)
    patch report_subscription_path, params: { report_subscription: { enabled: "1", frequency: "weekly" } }
    assert_redirected_to report_subscription_path
    assert area.reload.report_subscription.enabled?
    sign_in(@brand.store_user)
    assert_no_difference "ReportSubscription.count" do
      patch report_subscription_path, params: { report_subscription: { enabled: "1" } }
      assert_response :redirect
    end
    sign_in(@brand.hq)
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    get report_subscription_path
    assert_response :redirect
  end
end
