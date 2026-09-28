# frozen_string_literal: true

class CreateTenantSamlSettingsAndNullablePassword < ActiveRecord::Migration[8.1]
  def change
    create_table :tenant_saml_settings do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.boolean :sso_enforced, null: false, default: false
      t.string :idp_entity_id
      t.string :idp_sso_target_url
      t.text :idp_cert
      t.string :email_attribute

      t.timestamps
    end

    change_column_null :users, :password_digest, true
  end
end
