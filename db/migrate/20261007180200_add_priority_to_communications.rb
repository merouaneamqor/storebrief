class AddPriorityToCommunications < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:communications, :priority)

    add_column :communications, :priority, :string, default: "routine", null: false
  end

  def down
    remove_column :communications, :priority if column_exists?(:communications, :priority)
  end
end
