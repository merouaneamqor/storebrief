class DropWhatsappIntakes < ActiveRecord::Migration[8.1]
  def up
    drop_table :whatsapp_intakes, if_exists: true
  end

  def down
    create_table :whatsapp_intakes do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :communication, foreign_key: { on_delete: :nullify }
      t.text :raw_text, null: false
      t.string :status, null: false, default: "inbox"
      t.timestamps
    end
  end
end
