class CreateAuditTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_templates do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :description_fr
      t.text :description_ar
      t.jsonb :sections, null: false, default: []
      t.timestamps
    end

    add_reference :visits, :audit_template, foreign_key: true
  end
end
