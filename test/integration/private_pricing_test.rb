require "test_helper"

class PrivatePricingTest < ActionDispatch::IntegrationTest
  PRICES = %w[199 349 499].freeze

  setup do
    host! "localhost"
    PricingPlan.delete_all
    { "starter" => 199, "business" => 349, "enterprise" => 499, "grand_compte" => nil }.each_with_index do |(k, price), i|
      PricingPlan.create!(key: k, position: i + 1, unit_price: price)
    end
    @tenant = create_tenant("Pricing Co", "pricing-co")
    @region = @tenant.org_units.create!(name: "Casa", unit_type: "region")
    @super = create_user(@tenant, org_unit: @region, role: :hq, email: "root@pricing.test", super_admin: true)
    @hq = create_user(@tenant, org_unit: @region, role: :hq, email: "hq@pricing.test")
  end

  # Authorization

  test "super admin can view and update default prices with history and audit" do
    sign_in @super
    plan = PricingPlan.find_by!(key: "starter")
    get admin_pricing_plans_path(format: :json)
    assert_response :success
    assert_includes JSON.parse(response.body).map { |p| p["unit_price"].to_i }, 199

    assert_difference -> { plan.versions.count } => 1, -> { PricingAuditLog.count } => 1 do
      patch admin_pricing_plan_path(plan), params: { pricing_plan: { unit_price: "210" } }
    end
    assert_equal 210, plan.reload.unit_price
    assert_equal @super.id, PricingAuditLog.last.user_id
  end

  test "regular HQ admin is forbidden from pricing endpoints" do
    sign_in @hq
    plan = PricingPlan.find_by!(key: "starter")
    get admin_pricing_plans_path
    assert_response :forbidden
    assert_no_match(/199/, response.body)
    patch admin_pricing_plan_path(plan), params: { pricing_plan: { unit_price: "1" } }
    assert_response :forbidden
    assert_equal 199, plan.reload.unit_price
    get admin_quotations_path
    assert_response :forbidden
    get admin_pricing_audit_logs_path
    assert_response :forbidden
  end

  test "anonymous users are sent to login and see no prices" do
    [ admin_pricing_plans_path, admin_quotations_path, admin_pricing_audit_logs_path ].each do |path|
      get path
      assert_redirected_to login_path
    end
  end

  test "store users cannot reach quotations or pricing" do
    store = @tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: @region)
    user = create_user(@tenant, org_unit: store, role: :store, email: "store@pricing.test")
    sign_in user
    get admin_quotations_path
    assert_response :redirect
    assert_no_match(/199/, response.body)
  end

  test "mass assignment cannot change plan key or currency" do
    sign_in @super
    plan = PricingPlan.find_by!(key: "starter")
    patch admin_pricing_plan_path(plan), params: { pricing_plan: { key: "business", currency: "EUR", unit_price: "200" } }
    assert_equal "starter", plan.reload.key
    assert_equal "MAD", plan.currency
  end

  test "invalid prices are rejected" do
    plan = PricingPlan.find_by!(key: "starter")
    assert_not plan.update(unit_price: -5)
    assert_not plan.update(unit_price: 0)
  end

  # Confidentiality

  test "public plans page and landing page contain no prices" do
    [ plans_path, root_path, resources_path ].each do |path|
      get path
      assert_response :success
      PRICES.each { |p| assert_no_match(/\b#{p}\b/, response.body, "#{p} leaked on #{path}") }
      assert_no_match(/MAD|DH\b|per store|par magasin/i, response.body) if path == plans_path
    end
    get plans_path
    %w[Starter Business Enterprise Grand\ compte].each { |n| assert_match n, response.body }
    assert_match "Demander une démonstration", response.body
    assert_match "Obtenir une offre personnalisée", response.body
    assert_match "Contacter notre équipe commerciale", response.body
    assert_no_match(/application\/ld\+json/, response.body)
  end

  test "plans page leaks nothing in other locales" do
    %w[en es ar].each do |loc|
      patch locale_path, params: { locale: loc }
      get plans_path
      assert_response :success
      PRICES.each { |p| assert_no_match(/\b#{p}\b/, response.body) }
    end
  end

  test "public assets and locales do not contain the confidential prices" do
    files = Dir[Rails.root.join("app/assets/**/*.{js,css,scss,json}"), Rails.root.join("app/javascript/**/*"),
                Rails.root.join("config/locales/pricing.*.yml"), Rails.root.join("app/views/plans/*")]
    files.select { |f| File.file?(f) }.each do |f|
      assert_no_match(/\b(199|349|499)\b/, File.read(f), "#{f} exposes a price")
    end
  end

  test "admin error for forbidden user does not leak" do
    sign_in @hq
    get admin_pricing_plan_path(PricingPlan.first)
    assert_response :forbidden
    assert_no_match(/199|349|499|unit_price/, response.body)
  end

  # Business logic

  test "per-store calculations" do
    assert_equal 1990, Vazivo::Pricing.monthly_total(10, 199)
    assert_equal 23_880, Vazivo::Pricing.annual_total(10, 199)
    assert_equal 3490, Vazivo::Pricing.monthly_total(10, 349)
    assert_equal 41_880, Vazivo::Pricing.annual_total(10, 349)
    assert_equal 4990, Vazivo::Pricing.monthly_total(10, 499)
    assert_equal 59_880, Vazivo::Pricing.annual_total(10, 499)
    assert_equal 1791, Vazivo::Pricing.monthly_total(10, 199, 10)
  end

  test "quotations snapshot price and support custom pricing" do
    plan = PricingPlan.find_by!(key: "business")
    q = Quotation.create!(pricing_plan: plan, customer_name: "Acme", store_count: 10)
    assert_equal 349, q.unit_price
    assert_equal "draft", q.status

    custom = Quotation.create!(pricing_plan: PricingPlan.find_by!(key: "grand_compte"),
                               customer_name: "Big", store_count: 200, unit_price: 150)
    assert_equal 30_000, custom.monthly_total

    assert_not Quotation.new(pricing_plan: PricingPlan.find_by!(key: "grand_compte"),
                             customer_name: "Big", store_count: 5).valid?
  end

  test "changing default price does not reprice existing quotations or erase history" do
    plan = PricingPlan.find_by!(key: "business")
    q = Quotation.create!(pricing_plan: plan, customer_name: "Acme", store_count: 10)
    Current.user = @super
    versions_before = plan.versions.count
    plan.update!(unit_price: 400)
    assert_equal 349, q.reload.unit_price
    assert_equal 3490, q.monthly_total
    assert_equal versions_before + 1, plan.versions.count
    assert_equal 400, plan.versions.order(:id).last.unit_price
    assert_raises(ActiveRecord::ReadOnlyRecord) { plan.versions.first.destroy }
  ensure
    Current.user = nil
  end

  test "discount is capped by the approved maximum and issued quotations are locked" do
    plan = PricingPlan.find_by!(key: "starter")
    assert_not Quotation.new(pricing_plan: plan, customer_name: "A", store_count: 1, discount_percent: 5).valid?
    plan.update!(max_discount_percent: 10)
    q = Quotation.create!(pricing_plan: plan, customer_name: "A", store_count: 1, discount_percent: 5)
    q.issue!
    assert_not q.update(store_count: 99)
    q.reload.void!
    assert_equal "void", q.status
  end

  test "super admin can create a quotation through the admin UI" do
    sign_in @super
    plan = PricingPlan.find_by!(key: "starter")
    assert_difference -> { Quotation.count } => 1 do
      post admin_quotations_path, params: { quotation: { pricing_plan_id: plan.id, customer_name: "Acme", store_count: 4 } }
    end
    assert_equal @super, Quotation.last.created_by
  end

  # Lead form

  test "lead form stores plan, country and requirements" do
    assert_difference -> { DemoRequest.count } => 1 do
      post demo_requests_path, params: { demo_request: lead_params(requested_plan: "business") }
    end
    assert_redirected_to root_path(anchor: "demo")
    follow_redirect!
    PRICES.each { |p| assert_no_match(/\b#{p}\b/, response.body) }
    assert_equal "business", DemoRequest.last.requested_plan
  end

  test "lead form rejects unknown or disabled plans and invalid input" do
    PricingPlan.find_by!(key: "starter").update!(active_for_sales: false)
    assert_no_difference -> { DemoRequest.count } do
      post demo_requests_path, params: { demo_request: lead_params(requested_plan: "starter") }
      assert_response :unprocessable_entity
      post demo_requests_path, params: { demo_request: lead_params(requested_plan: "free") }
      assert_response :unprocessable_entity
      post demo_requests_path, params: { demo_request: lead_params(email: "nope") }
      assert_response :unprocessable_entity
    end
  end

  test "honeypot submissions are silently dropped" do
    assert_no_difference -> { DemoRequest.count } do
      post demo_requests_path, params: { website: "http://spam", demo_request: lead_params }
    end
  end

  private

  def lead_params(**over)
    { name: "Sara", company: "Atlas Retail", email: "sara@atlas.test", store_count: 12, country: "Maroc",
      requirements: "SSO", preferred_locale: "fr", privacy_consent: "1" }.merge(over)
  end
end
