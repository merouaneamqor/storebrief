class AddCorrectiveActions < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :corrective_deadline_days, :integer, default: 3, null: false

    add_reference :communications, :visit, foreign_key: true, null: true
    add_reference :communications, :source_delivery, foreign_key: { to_table: :deliveries }, null: true
    add_reference :communications, :source_checklist_item_response,
                  foreign_key: { to_table: :checklist_item_responses }, null: true

    add_index :communications, :source_delivery_id,
              unique: true,
              where: "source_delivery_id IS NOT NULL AND source = 'corrective'",
              name: "index_communications_unique_corrective_source_delivery"
    add_index :communications, :source_checklist_item_response_id,
              unique: true,
              where: "source_checklist_item_response_id IS NOT NULL AND source = 'corrective'",
              name: "index_communications_unique_corrective_checklist_item"
  end
end
