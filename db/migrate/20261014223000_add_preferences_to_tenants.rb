# frozen_string_literal: true

class AddPreferencesToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :preferences, :jsonb, null: false, default: {}
  end
end
