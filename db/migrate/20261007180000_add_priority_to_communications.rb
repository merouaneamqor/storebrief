class AddPriorityToCommunications < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :priority, :string, default: "routine", null: false
  end
end
