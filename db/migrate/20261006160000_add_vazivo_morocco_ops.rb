class AddVazivoMoroccoOps < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :ramadan_mode, :boolean, null: false, default: false
    add_column :tenants, :opens_at, :string, null: false, default: "09:00"
    add_column :tenants, :closes_at, :string, null: false, default: "21:00"
    add_column :tenants, :ramadan_opens_at, :string, null: false, default: "12:00"
    add_column :tenants, :ramadan_closes_at, :string, null: false, default: "01:00"

    create_table :playbooks do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :key, null: false
      t.string :title_fr, null: false
      t.string :title_ar
      t.string :title_darija
      t.text :description_fr, null: false
      t.text :description_ar
      t.text :description_darija
      t.jsonb :steps, null: false, default: []
      t.timestamps
      t.index [ :tenant_id, :key ], unique: true
    end

    add_column :communications, :title_darija, :string
    add_column :communications, :body_darija, :text
    add_column :communications, :source, :string, null: false, default: "compose"
    add_column :communications, :requires_proof, :boolean, null: false, default: false
    add_column :communications, :due_at, :datetime
    add_reference :communications, :playbook, foreign_key: { on_delete: :nullify }

    add_column :deliveries, :awareness, :string, null: false, default: "pending"
    add_reference :deliveries, :assignee, foreign_key: { to_table: :users }
    add_column :deliveries, :due_at, :datetime
    add_column :deliveries, :escalation_level, :integer, null: false, default: 0
    add_column :deliveries, :escalated_at, :datetime
    add_column :deliveries, :verdict, :string
    add_column :deliveries, :verdict_note, :text
    add_reference :deliveries, :validated_by, foreign_key: { to_table: :users }
    add_column :deliveries, :validated_at, :datetime

    add_column :checklists, :title_darija, :string
    add_column :checklists, :description_darija, :text
    add_column :checklists, :campaign_on, :date
    add_reference :checklists, :playbook, foreign_key: { on_delete: :nullify }

    add_column :checklist_items, :title_darija, :string

    add_reference :checklist_deliveries, :assignee, foreign_key: { to_table: :users }
    add_column :checklist_deliveries, :due_at, :datetime
    add_column :checklist_deliveries, :escalation_level, :integer, null: false, default: 0
    add_column :checklist_deliveries, :escalated_at, :datetime

    create_table :whatsapp_intakes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :communication, foreign_key: { on_delete: :nullify }
      t.text :raw_text, null: false
      t.string :status, null: false, default: "inbox"
      t.timestamps
    end

    create_table :escalation_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.integer :level, null: false
      t.string :notified_role, null: false
      t.timestamps
    end
  end
end
