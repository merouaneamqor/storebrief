# frozen_string_literal: true

class AddCndpPrivacyFields < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.datetime :privacy_notice_accepted_at
      t.boolean :operational_email_opt_out, null: false, default: false
      t.datetime :whatsapp_alerts_consent_at
      t.datetime :push_alerts_consent_at
    end

    change_table :demo_requests, bulk: true do |t|
      t.datetime :privacy_consent_at
      t.boolean :marketing_contact_consent, null: false, default: false
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE users SET privacy_notice_accepted_at = created_at WHERE privacy_notice_accepted_at IS NULL
        SQL
      end
    end
  end
end
