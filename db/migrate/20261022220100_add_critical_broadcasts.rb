class AddCriticalBroadcasts < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :critical_broadcast, :boolean, null: false, default: false
    add_column :communications, :requires_acknowledgement, :boolean, null: false, default: false
    add_column :communications, :broadcast_email, :boolean, null: false, default: false
    add_column :communications, :broadcast_whatsapp, :boolean, null: false, default: false
    add_column :deliveries, :acknowledged_at, :datetime
    add_reference :deliveries, :acknowledged_by, foreign_key: { to_table: :users }
  end
end
