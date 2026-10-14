class AddStoreFormatAndClusterToOrgUnits < ActiveRecord::Migration[8.1]
  def change
    add_column :org_units, :store_format, :string unless column_exists?(:org_units, :store_format)
    add_column :org_units, :cluster_key, :string unless column_exists?(:org_units, :cluster_key)
    unless index_exists?(:org_units, [ :tenant_id, :store_format ], name: "index_org_units_on_tenant_id_and_store_format")
      add_index :org_units, [ :tenant_id, :store_format ], name: "index_org_units_on_tenant_id_and_store_format"
    end
    unless index_exists?(:org_units, [ :tenant_id, :cluster_key ], name: "index_org_units_on_tenant_id_and_cluster_key")
      add_index :org_units, [ :tenant_id, :cluster_key ], name: "index_org_units_on_tenant_id_and_cluster_key"
    end
  end
end
