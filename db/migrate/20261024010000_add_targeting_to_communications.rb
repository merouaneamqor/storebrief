class AddTargetingToCommunications < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :targeting, :jsonb, default: {}, null: false
  end
end
