class AddTaglineToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :tagline, :string
  end
end
