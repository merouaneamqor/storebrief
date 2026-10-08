class CreateChecklistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_items do |t|
      t.references :checklist, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :title_fr, null: false
      t.string :title_ar
      t.boolean :requires_photo, null: false, default: false

      t.timestamps
    end
  end
end
