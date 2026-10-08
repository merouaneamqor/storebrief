class CreateDemoRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :demo_requests do |t|
      t.string :name, null: false
      t.string :company, null: false
      t.string :email
      t.string :phone
      t.integer :store_count
      t.string :preferred_locale, null: false, default: "fr"
      t.string :status, null: false, default: "new"

      t.timestamps
    end

    add_index :demo_requests, :created_at
  end
end
