class CreateBriefTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :brief_templates do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :body_fr
      t.text :body_ar
      t.string :format, null: false, default: "task"
      t.string :priority, null: false, default: "routine"
      t.boolean :requires_proof, null: false, default: false
      t.jsonb :questions, null: false, default: []
      t.timestamps
    end
    add_index :brief_templates, %i[tenant_id name]
  end
end
