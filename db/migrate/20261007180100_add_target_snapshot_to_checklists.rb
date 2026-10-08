class AddTargetSnapshotToChecklists < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:checklists, :target_snapshot)

    add_column :checklists, :target_snapshot, :jsonb, null: false, default: {}
  end

  def down
    remove_column :checklists, :target_snapshot if column_exists?(:checklists, :target_snapshot)
  end
end
