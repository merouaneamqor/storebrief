class AddDependsOnToCommunications < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:communications, :depends_on_id)

    add_reference :communications, :depends_on, foreign_key: { to_table: :communications }
  end

  def down
    remove_reference :communications, :depends_on if column_exists?(:communications, :depends_on_id)
  end
end
