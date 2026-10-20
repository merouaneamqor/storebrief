require "test_helper"

class OrgUnitFormatClusterTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("fmt-cluster", features: { briefs: true, knowledge_base: true })
    @area = @brand.tenant.org_units.create!(name: "Casa Centre", unit_type: "area", parent: @brand.region)
    @brand.store.update!(parent: @area)
    @other = build_brand("fmt-other")
  end

  test "HQ edits format and cluster on a store" do
    sign_in @brand.hq
    get edit_org_unit_path(@brand.store)
    assert_response :success

    patch org_unit_path(@brand.store), params: { org_unit: { store_format: " Express ", cluster_key: "casa-sud" } }
    assert_redirected_to org_units_path
    @brand.store.reload
    assert_equal "Express", @brand.store.store_format
    assert_equal "casa-sud", @brand.store.cluster_key

    get org_units_path
    assert_includes response.body, "casa-sud"
  end

  test "update permits only format and cluster" do
    sign_in @brand.hq
    patch org_unit_path(@brand.store), params: { org_unit: { store_format: "x", name: "Hacked", unit_type: "region" } }
    @brand.store.reload
    assert_equal "Maarif", @brand.store.name
    assert_equal "store", @brand.store.unit_type
  end

  test "non HQ users cannot edit" do
    sign_in @brand.store_user
    patch org_unit_path(@brand.store), params: { org_unit: { store_format: "hacked" } }
    assert_redirected_to app_root_path
    assert_nil @brand.store.reload.store_format
  end

  test "HQ cannot edit another tenant store or a non store unit" do
    sign_in @brand.hq
    patch org_unit_path(@other.store), params: { org_unit: { store_format: "hacked" } }
    assert_response :not_found
    assert_nil @other.store.reload.store_format

    get edit_org_unit_path(@area)
    assert_response :not_found
  end

  test "compose picker lists areas and shows format and cluster" do
    @brand.store.update!(store_format: "express", cluster_key: "casa-sud")
    sign_in @brand.hq
    get new_communication_path
    assert_response :success
    assert_includes response.body, "Casa Centre"
    assert_includes response.body, "express"
    assert_includes response.body, "casa-sud"
  end

  test "targeting an area resolves its stores filtered by format and cluster" do
    @brand.store.update!(store_format: "express", cluster_key: "casa-sud")
    flagship = @brand.tenant.org_units.create!(
      name: "Anfa", unit_type: "store", parent: @area, store_format: "flagship", cluster_key: "casa-nord"
    )

    assert_equal [ @brand.store.id, flagship.id ].sort,
                 Vazivo::Assignment.resolve_store_ids(@brand.tenant, org_unit_ids: [ @area.id ]).sort
    assert_equal [ flagship.id ],
                 Vazivo::Assignment.resolve_store_ids(@brand.tenant, org_unit_ids: [ @area.id ], store_format: "flagship")
    assert_equal [ @brand.store.id ],
                 Vazivo::Assignment.resolve_store_ids(@brand.tenant, org_unit_ids: [ @area.id ], cluster: "casa-sud")
    assert_empty Vazivo::Assignment.resolve_store_ids(@brand.tenant, org_unit_ids: [ @area.id ], store_format: "express", cluster: "casa-nord")
  end

  test "KB store tags come from the edited format and cluster" do
    sign_in @brand.hq
    patch org_unit_path(@brand.store), params: { org_unit: { store_format: "express", cluster_key: "casa-sud" } }

    assert_equal %w[express casa-sud], Vazivo::KbAccess.store_tags_for(@brand.store.reload)

    get new_kb_article_path
    assert_response :success
    assert_includes response.body, "casa-sud"
  end
end
