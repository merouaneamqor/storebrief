class CreateChecklistDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_deliveries do |t|
      t.references :checklist, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at
      t.string :client_uuid

      t.timestamps
    end

    add_index :checklist_deliveries, [:checklist_id, :org_unit_id], unique: true
    add_index :checklist_deliveries, :client_uuid, unique: true, where: "client_uuid IS NOT NULL"
  end
end
