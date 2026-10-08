class AddLocaleAndWhatsappToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string, null: false, default: "fr"
    add_column :users, :whatsapp_phone, :string
  end
end
