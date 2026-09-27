class CreateCommunications < ActiveRecord::Migration[8.1]
  def change
    create_table :communications do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :body, null: false
      t.string :format, null: false
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :communications, [:tenant_id, :status]
  end
end
