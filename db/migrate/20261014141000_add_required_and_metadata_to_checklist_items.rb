class AddRequiredAndMetadataToChecklistItems < ActiveRecord::Migration[8.1]
  def change
    add_column :checklist_items, :required, :boolean, default: false, null: false
    add_column :checklist_items, :metadata, :jsonb, default: {}, null: false
  end
end
