module Vazivo
  # Single authoritative place for per-store pricing math and default price lookup.
  # Prices are confidential: never call from public controllers or views.
  module Pricing
    module_function

    def monthly_total(store_count, unit_price, discount_percent = 0)
      gross = BigDecimal(store_count.to_s) * BigDecimal(unit_price.to_s)
      (gross * (1 - BigDecimal(discount_percent.to_s) / 100)).round(2)
    end

    def annual_total(store_count, unit_price, discount_percent = 0)
      monthly_total(store_count, unit_price, discount_percent) * 12
    end

    def default_unit_price(key)
      PricingPlan.find_by(key: key)&.unit_price
    end
  end
end
