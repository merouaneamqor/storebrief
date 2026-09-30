class CreateOrgUnits < ActiveRecord::Migration[8.1]
  def change
    create_table :org_units do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :org_units }
      t.string :name, null: false
      t.string :unit_type, null: false

      t.timestamps
    end

    add_index :org_units, [ :tenant_id, :unit_type ]
  end
end
