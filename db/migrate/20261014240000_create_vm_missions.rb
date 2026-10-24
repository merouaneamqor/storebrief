class CreateVmMissions < ActiveRecord::Migration[8.1]
  def change
    create_table :vm_missions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :instructions_fr, null: false
      t.text :instructions_ar
      t.date :deadline_on, null: false
      t.string :status, null: false, default: "open"

      t.timestamps
    end

    add_index :vm_missions, [ :tenant_id, :deadline_on ]
    add_index :vm_missions, [ :tenant_id, :status ]

    create_table :vm_mission_targets do |t|
      t.references :vm_mission, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true

      t.timestamps
    end

    add_index :vm_mission_targets, [ :vm_mission_id, :org_unit_id ], unique: true,
              name: "index_vm_mission_targets_on_mission_and_store"
  end
end
