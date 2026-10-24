class CreateExportLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :export_logs do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :source, null: false
      t.string :output_format, null: false
      t.jsonb :filters, null: false, default: {}
      t.integer :row_count, null: false
      t.datetime :created_at, null: false
      t.index [ :tenant_id, :created_at ]
    end
  end
end
