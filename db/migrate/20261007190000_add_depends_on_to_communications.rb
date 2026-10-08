class AddDependsOnToCommunications < ActiveRecord::Migration[8.1]
  def up
    return if column_exists?(:communications, :depends_on_id)

    add_reference :communications, :depends_on, null: true, index: true
    add_foreign_key :communications, :communications, column: :depends_on_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :communications, column: :depends_on_id if foreign_key_exists?(:communications, column: :depends_on_id)
    remove_reference :communications, :depends_on if column_exists?(:communications, :depends_on_id)
  end
end
