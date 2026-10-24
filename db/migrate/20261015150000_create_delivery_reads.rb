class CreateDeliveryReads < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_reads do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :delivery, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :read_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :delivery_reads, [ :delivery_id, :user_id ], unique: true
    add_index :delivery_reads, [ :tenant_id, :read_at ]
  end
end
