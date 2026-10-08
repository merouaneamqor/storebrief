class AddSuperAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :super_admin, :boolean, default: false, null: false
    add_index :users, :email, unique: true, where: "super_admin = true", name: "index_users_on_super_admin_email"
  end
end
