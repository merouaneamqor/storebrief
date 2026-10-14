class CreateDeliveryEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :delivery, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :delivery_events, [ :delivery_id, :created_at ]
    add_index :delivery_events, [ :tenant_id, :created_at ]
  end
end
