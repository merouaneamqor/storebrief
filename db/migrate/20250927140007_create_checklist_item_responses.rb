class CreateChecklistItemResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_item_responses do |t|
      t.references :checklist_delivery, null: false, foreign_key: true
      t.references :checklist_item, null: false, foreign_key: true
      t.boolean :completed, null: false, default: false
      t.text :notes
      t.string :client_uuid

      t.timestamps
    end

    add_index :checklist_item_responses, [ :checklist_delivery_id, :checklist_item_id ], unique: true, name: "index_item_responses_on_delivery_and_item"
    add_index :checklist_item_responses, :client_uuid, unique: true, where: "client_uuid IS NOT NULL"
  end
end
