class CreateDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :deliveries do |t|
      t.references :communication, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.datetime :completed_at

      t.timestamps
    end

    add_index :deliveries, [:communication_id, :org_unit_id], unique: true
  end
end
