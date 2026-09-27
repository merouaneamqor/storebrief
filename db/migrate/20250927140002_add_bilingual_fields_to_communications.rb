class AddBilingualFieldsToCommunications < ActiveRecord::Migration[8.1]
  def up
    add_column :communications, :title_fr, :string
    add_column :communications, :title_ar, :string
    add_column :communications, :body_fr, :text
    add_column :communications, :body_ar, :text

    execute <<~SQL
      UPDATE communications SET title_fr = title, body_fr = body
    SQL

    change_column_null :communications, :title_fr, false
    change_column_null :communications, :body_fr, false

    remove_column :communications, :title
    remove_column :communications, :body
  end

  def down
    add_column :communications, :title, :string
    add_column :communications, :body, :text

    execute <<~SQL
      UPDATE communications SET title = title_fr, body = body_fr
    SQL

    change_column_null :communications, :title, false
    change_column_null :communications, :body, false

    remove_column :communications, :title_fr
    remove_column :communications, :title_ar
    remove_column :communications, :body_fr
    remove_column :communications, :body_ar
  end
end
