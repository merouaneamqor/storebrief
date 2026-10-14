class AddTaskDependencies < ActiveRecord::Migration[8.1]
  def change
    add_reference :communications, :depends_on_communication,
                  foreign_key: { to_table: :communications }, null: true
    add_column :deliveries, :dependency_cleared_at, :datetime
    add_column :deliveries, :dependency_cleared_by_id, :bigint

    add_foreign_key :deliveries, :users, column: :dependency_cleared_by_id
    add_index :deliveries, :dependency_cleared_by_id
  end
end
