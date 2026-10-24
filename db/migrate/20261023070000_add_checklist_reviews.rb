class AddChecklistReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :checklist_deliveries, :verdict, :string
    add_column :checklist_deliveries, :verdict_note, :text
    add_reference :checklist_deliveries, :validated_by, foreign_key: { to_table: :users }
    add_column :checklist_deliveries, :validated_at, :datetime

    create_table :checklist_delivery_comments do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :checklist_delivery, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :checklist_delivery_comments }
      t.text :body, null: false
      t.jsonb :mentioned_user_ids, null: false, default: []
      t.timestamps
    end

    create_table :checklist_delivery_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :checklist_delivery, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
