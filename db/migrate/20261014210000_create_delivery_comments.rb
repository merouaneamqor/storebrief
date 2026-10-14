class CreateDeliveryComments < ActiveRecord::Migration[8.1]
  def change
    create_table :delivery_comments do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :delivery, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :delivery_comments }
      t.text :body, null: false
      t.jsonb :mentioned_user_ids, null: false, default: []
      t.datetime :created_at, null: false
    end

    add_index :delivery_comments, [ :delivery_id, :created_at ]
    add_index :delivery_comments, [ :tenant_id, :created_at ]
    add_index :delivery_comments, [ :parent_id, :created_at ]
  end
end
