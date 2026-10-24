# Append-only history of default price changes.
class PricingPlanVersion < ApplicationRecord
  belongs_to :pricing_plan
  belongs_to :changed_by, class_name: "User", optional: true

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord }
end
