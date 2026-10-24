class CreateOidcSso < ActiveRecord::Migration[8.1]
  def change
    create_table :tenant_oidc_settings do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.boolean :sso_enforced, null: false, default: false
      t.boolean :jit_enabled, null: false, default: false
      t.string :issuer
      t.string :client_id
      t.text :client_secret_ciphertext
      t.string :authorization_endpoint
      t.string :token_endpoint
      t.string :jwks_uri
      t.jsonb :role_mappings, null: false, default: []
      t.timestamps
    end
    create_table :oidc_identities do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :issuer, null: false
      t.string :subject, null: false
      t.boolean :admin_linked, null: false, default: false
      t.timestamps
    end
    add_index :oidc_identities, [ :tenant_id, :issuer, :subject ], unique: true, name: "index_oidc_identities_on_tenant_issuer_subject"
    add_reference :memberships, :oidc_identity, foreign_key: true
    create_table :oidc_login_attempts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :state_digest, null: false, index: { unique: true }
      t.string :browser_digest, null: false
      t.string :nonce_digest, null: false
      t.text :code_verifier_ciphertext, null: false
      t.string :redirect_uri, null: false
      t.string :issuer, null: false
      t.string :client_id, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
  end
end
