class CreateNotificationLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_logs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :notifiable_type, null: false
      t.bigint :notifiable_id, null: false
      t.string :channel, null: false, default: "whatsapp"
      t.string :phone
      t.text :message, null: false
      t.string :status, null: false, default: "stubbed"

      t.timestamps
    end

    add_index :notification_logs, [:notifiable_type, :notifiable_id]
  end
end
