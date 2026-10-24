class CreateReportSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :report_subscriptions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :frequency, null: false, default: "weekly"
      t.boolean :csv_attachment, null: false, default: false
      t.datetime :next_delivery_at
      t.datetime :last_sent_at
      t.string :last_sent_period
      t.timestamps
      t.index [ :enabled, :next_delivery_at ]
    end
  end
end
