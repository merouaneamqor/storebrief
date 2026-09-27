class CreateMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true
      t.string :role, null: false

      t.timestamps
    end

    add_index :memberships, [:user_id, :org_unit_id], unique: true
  end
end
