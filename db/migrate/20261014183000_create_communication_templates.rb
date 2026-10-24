class CreateCommunicationTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :communication_templates do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :body_fr, null: false, default: ""
      t.text :body_ar
      t.string :format, null: false, default: "task"
      t.boolean :requires_proof, null: false, default: false
      t.string :priority, null: false, default: "routine"
      t.jsonb :questions, null: false, default: []

      t.timestamps
    end

    add_index :communication_templates, [ :tenant_id, :title_fr ]

    add_reference :communications, :communication_template, foreign_key: true
  end
end
