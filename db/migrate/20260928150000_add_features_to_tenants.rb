# frozen_string_literal: true

class AddFeaturesToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :features, :jsonb, null: false, default: {}
  end
end
