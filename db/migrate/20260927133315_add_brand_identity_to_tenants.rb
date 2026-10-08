class AddBrandIdentityToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :brand_name, :string, null: false, default: "StoreBrief"
  end
end
