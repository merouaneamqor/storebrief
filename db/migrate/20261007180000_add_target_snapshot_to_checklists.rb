class AddTargetSnapshotToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_column :checklists, :target_snapshot, :jsonb, null: false, default: {}
  end
end
