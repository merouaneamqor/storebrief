# frozen_string_literal: true

require "test_helper"

class TenantHqWidgetsTest < ActiveSupport::TestCase
  setup do
    @tenant = create_tenant("Widgets Co", "widgets-co")
  end

  test "defaults enable the sensible HQ widget set" do
    assert_equal Tenant.default_hq_widgets, @tenant.hq_widgets
    Tenant::HQ_WIDGETS.each_key do |key|
      assert @tenant.hq_widget?(key), "#{key} should default on"
    end
  end

  test "hq widget preferences persist on the tenant" do
    @tenant.hq_widgets = {
      "campaign" => false,
      "store_status" => true,
      "compliance" => false,
      "monitoring" => true,
      "exceptions" => true,
      "podium" => false
    }
    assert @tenant.save

    @tenant.reload
    assert_not @tenant.hq_widget?(:campaign)
    assert @tenant.hq_widget?(:store_status)
    assert_not @tenant.hq_widget?(:compliance)
    assert @tenant.hq_widget?(:monitoring)
    assert @tenant.hq_widget?(:exceptions)
    assert_not @tenant.hq_widget?(:podium)
    assert_equal(
      {
        "campaign" => false,
        "store_status" => true,
        "compliance" => false,
        "monitoring" => true,
        "exceptions" => true,
        "podium" => false
      },
      @tenant.preferences["hq_widgets"]
    )
  end

  test "missing form keys are treated as off and unknown preference keys are dropped" do
    @tenant.preferences = {
      "noise" => true,
      "hq_widgets" => { "campaign" => false, "mystery" => true, "exceptions" => "1" }
    }
    assert @tenant.save
    @tenant.reload

    assert_nil @tenant.preferences["noise"]
    assert_equal({ "campaign" => false, "exceptions" => true }, @tenant.preferences["hq_widgets"])
    assert_not @tenant.hq_widget?(:campaign)
    assert @tenant.hq_widget?(:exceptions)
    assert @tenant.hq_widget?(:podium)

    @tenant.hq_widgets = { "exceptions" => "1" }
    assert @tenant.save
    @tenant.reload
    assert @tenant.hq_widget?(:exceptions)
    assert_not @tenant.hq_widget?(:campaign)
    assert_not @tenant.hq_widget?(:podium)
  end

  test "unknown widget keys are never enabled" do
    assert_not @tenant.hq_widget?(:not_a_widget)
  end
end
