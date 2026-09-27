class CreateChecklists < ActiveRecord::Migration[8.1]
  def change
    create_table :checklists do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :checklist_template, foreign_key: true
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :description_fr
      t.text :description_ar
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :checklists, [:tenant_id, :status]
  end
end
