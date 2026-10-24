# Public plans page. Never loads prices: only plan keys and sales availability.
class PlansController < ApplicationController
  skip_before_action :require_login
  skip_before_action :bind_session_tenant
  skip_before_action :require_privacy_acceptance
  layout "marketing"

  RECOMMENDED = "business".freeze

  def show
    @plan_keys = PricingPlan.ordered.where(active_for_sales: true).pluck(:key)
    @recommended = RECOMMENDED
  end
end
