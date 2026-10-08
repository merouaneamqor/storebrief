class CreateVisits < ActiveRecord::Migration[8.1]
  def change
    create_table :visits do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true
      t.references :auditor, null: false, foreign_key: { to_table: :users }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :planned_at, null: false
      t.string :status, null: false, default: "planned"
      t.text :notes
      t.text :cancel_reason
      t.datetime :cancelled_at
      t.timestamps
      t.index [ :tenant_id, :planned_at ]
      t.index [ :tenant_id, :status ]
    end
  end
end
