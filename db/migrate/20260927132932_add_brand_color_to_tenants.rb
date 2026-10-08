class AddBrandColorToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :brand_color, :string, null: false, default: "#0c6b58"
  end
end
