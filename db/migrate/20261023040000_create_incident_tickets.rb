class CreateIncidentTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :ticket_categories do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :name, null: false
      t.string :department, null: false
      t.integer :sla_hours, null: false
      t.timestamps
    end
    add_index :ticket_categories, [ :tenant_id, :name ], unique: true
    create_table :incident_tickets do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true
      t.references :ticket_category, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :source, polymorphic: true
      t.string :title, null: false
      t.text :description, null: false
      t.string :department, null: false
      t.string :priority, null: false, default: "routine"
      t.string :status, null: false, default: "open"
      t.datetime :due_at, null: false
      t.datetime :resolved_at
      t.timestamps
    end
    create_table :ticket_events do |t|
      t.references :incident_ticket, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.string :from_value
      t.string :to_value
      t.timestamps
    end
    add_index :incident_tickets, [ :tenant_id, :status, :due_at ]
  end
end
