class CreateTenantRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :tenant_roles do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :base_role, null: false
      t.jsonb :capabilities, null: false, default: []
      t.timestamps
    end
    add_index :tenant_roles, [ :tenant_id, :name ], unique: true
    add_reference :memberships, :tenant_role, foreign_key: true
  end
end
