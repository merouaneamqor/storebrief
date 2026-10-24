class AddProofReviewToVmMissionTargets < ActiveRecord::Migration[8.1]
  def change
    change_table :vm_mission_targets, bulk: true do |t|
      t.string :status, null: false, default: "pending"
      t.string :verdict
      t.text :verdict_note
      t.datetime :submitted_at
      t.datetime :validated_at
      t.references :validated_by, foreign_key: { to_table: :users, on_delete: :nullify }
    end

    add_index :vm_mission_targets, [ :vm_mission_id, :status ]
  end
end
