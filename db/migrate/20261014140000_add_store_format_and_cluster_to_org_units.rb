class AddStoreFormatAndClusterToOrgUnits < ActiveRecord::Migration[8.1]
  def change
    add_column :org_units, :store_format, :string
    add_column :org_units, :cluster_key, :string
    add_index :org_units, [ :tenant_id, :store_format ], name: "index_org_units_on_tenant_id_and_store_format"
    add_index :org_units, [ :tenant_id, :cluster_key ], name: "index_org_units_on_tenant_id_and_cluster_key"
  end
end
