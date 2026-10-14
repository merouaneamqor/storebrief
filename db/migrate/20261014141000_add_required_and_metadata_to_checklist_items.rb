class AddRequiredAndMetadataToChecklistItems < ActiveRecord::Migration[8.1]
  def change
    # Idempotent: local/preview DBs may already have columns from a partial apply.
    add_column :checklist_items, :required, :boolean, default: false, null: false unless column_exists?(:checklist_items, :required)
    add_column :checklist_items, :metadata, :jsonb, default: {}, null: false unless column_exists?(:checklist_items, :metadata)
  end
end
