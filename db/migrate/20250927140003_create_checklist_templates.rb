class CreateChecklistTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :checklist_templates do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :category, null: false
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :description_fr
      t.text :description_ar
      t.jsonb :items, null: false, default: []

      t.timestamps
    end

    add_index :checklist_templates, [:tenant_id, :category]
  end
end
