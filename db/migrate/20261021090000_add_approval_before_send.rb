# HQ approval gate before a brief is sent or a playbook is deployed to stores.
class AddApprovalBeforeSend < ActiveRecord::Migration[8.1]
  def change
    change_table :communications do |t|
      t.string :review_status
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :reviewed_at
      t.text :review_note
    end

    create_table :playbook_deploy_requests do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :playbook, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :communication, foreign_key: { on_delete: :nullify }
      t.jsonb :deploy_params, null: false, default: {}
      t.string :review_status, null: false, default: "pending_review"
      t.datetime :reviewed_at
      t.text :review_note
      t.datetime :deployed_at
      t.timestamps
    end

    create_table :approval_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false
      t.text :note
      t.datetime :created_at, null: false
    end
  end
end
