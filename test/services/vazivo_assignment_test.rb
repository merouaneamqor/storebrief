require "test_helper"

class VazivoAssignmentTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("assign-bulk")
    @store_b = @brand.tenant.org_units.create!(
      name: "Anfa",
      unit_type: "store",
      parent: @brand.region,
      store_format: "flagship",
      cluster_key: "casa-center"
    )
    @brand.store.update!(store_format: "express", cluster_key: "casa-south")
    create_user(@brand.tenant, org_unit: @store_b, role: :store, email: "store-b@assign-bulk.test")
  end

  test "resolve expands region to stores then filters by format and cluster" do
    ids = Vazivo::Assignment.resolve_store_ids(
      @brand.tenant,
      org_unit_ids: [ @brand.region.id ],
      store_format: "flagship",
      cluster: "casa-center"
    )

    assert_equal [ @store_b.id ], ids
  end

  test "resolve keeps stores that have a membership with the given role" do
    ids = Vazivo::Assignment.resolve_store_ids(
      @brand.tenant,
      org_unit_ids: [ @brand.region.id ],
      role: "store"
    )

    assert_equal [ @brand.store.id, @store_b.id ].sort, ids.sort
  end

  test "preview returns store structs for a dry run" do
    preview = Vazivo::Assignment.preview(
      @brand.tenant,
      org_unit_ids: [ @brand.region.id ],
      store_format: "express"
    )

    assert_equal 1, preview.size
    store = preview.first
    assert_equal @brand.store.id, store.id
    assert_equal "Maarif", store.name
    assert_equal "express", store.store_format
    assert_equal "casa-south", store.cluster
  end

  test "resolve and preview stay inside the tenant" do
    other = build_brand("assign-other")
    other.store.update!(store_format: "flagship", cluster_key: "casa-center")

    ids = Vazivo::Assignment.resolve_store_ids(
      @brand.tenant,
      org_unit_ids: [ @brand.region.id, other.region.id ],
      store_format: "flagship"
    )
    preview = Vazivo::Assignment.preview(
      @brand.tenant,
      org_unit_ids: [ other.store.id ]
    )

    assert_equal [ @store_b.id ], ids
    assert_empty preview
  end

  test "send_to uses assignment filters for communications" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Promo flagship",
      body_fr: "Mettre en avant.",
      format: "task",
      status: "draft"
    )

    brief.send_to!([ @brand.region.id ], store_format: "flagship", cluster: "casa-center")

    assert_equal [ @store_b.id ], brief.deliveries.pluck(:org_unit_id)
  end

  test "send_to uses assignment filters for checklists" do
    checklist = @brand.tenant.checklists.create!(
      author: @brand.hq,
      title_fr: "Ouverture",
      status: "draft"
    )
    checklist.checklist_items.create!(position: 0, title_fr: "Lumières")

    checklist.send_to!([ @brand.region.id ], role: "store", store_format: "express")

    assert_equal [ @brand.store.id ], checklist.checklist_deliveries.pluck(:org_unit_id)
  end
end
