class AddTenantMailAndNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :tenant_mail_settings do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.string :from_email
      t.string :from_name
      t.string :smtp_address
      t.integer :smtp_port, default: 587, null: false
      t.string :smtp_domain
      t.string :smtp_username
      t.string :smtp_password
      t.string :smtp_authentication, default: "plain", null: false
      t.boolean :smtp_enable_starttls_auto, default: true, null: false
      t.boolean :use_platform, default: true, null: false
      t.timestamps
    end

    add_column :notification_logs, :billed, :boolean, default: false, null: false
    change_column_default :notification_logs, :channel, from: "whatsapp", to: "web_push"
  end
end
