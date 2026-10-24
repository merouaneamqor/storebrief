require "test_helper"

class VazivoKbAccessTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("kb-access-svc", features: { morocco_ops: true, knowledge_base: true })
    @tenant = @brand.tenant
    @category = @tenant.kb_categories.create!(title_fr: "SOP")
    @brand.store.update!(store_format: "express", cluster_key: "casa-south")

    @area = @tenant.org_units.create!(name: "Casa Area", unit_type: "area", parent: @brand.region)
    @brand.store.update!(parent: @area)
    @flagship = @tenant.org_units.create!(
      name: "Anfa",
      unit_type: "store",
      parent: @area,
      store_format: "flagship",
      cluster_key: "casa-center"
    )
    @area_user = create_user(@tenant, org_unit: @area, role: :area, email: "area@kb-access-svc.test")

    @open = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Ouverture generale",
      body_fr: "Pour tous.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: [],
      audience_store_tags: []
    )
    @store_role = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Guide magasin",
      body_fr: "Roles store.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store],
      audience_store_tags: []
    )
    @hq_role = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Note siege",
      body_fr: "HQ only.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[hq],
      audience_store_tags: []
    )
    @express_only = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "SOP express",
      body_fr: "Express only.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store],
      audience_store_tags: %w[express]
    )
    @flagship_only = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "SOP flagship",
      body_fr: "Flagship only.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store area],
      audience_store_tags: %w[flagship]
    )
  end

  test "store user cannot leak role-restricted or wrong store-tag articles" do
    assert Vazivo::KbAccess.allowed?(@open, user: @brand.store_user)
    assert Vazivo::KbAccess.allowed?(@store_role, user: @brand.store_user)
    assert Vazivo::KbAccess.allowed?(@express_only, user: @brand.store_user)
    assert_not Vazivo::KbAccess.allowed?(@hq_role, user: @brand.store_user)
    assert_not Vazivo::KbAccess.allowed?(@flagship_only, user: @brand.store_user)

    ids = Vazivo::KbAccess.apply(@tenant.kb_articles.published, user: @brand.store_user).pluck(:id)
    assert_includes ids, @open.id
    assert_includes ids, @express_only.id
    assert_not_includes ids, @hq_role.id
    assert_not_includes ids, @flagship_only.id
  end

  test "area user sees articles matching any managed store tag" do
    assert Vazivo::KbAccess.allowed?(@flagship_only, user: @area_user)
    assert Vazivo::KbAccess.allowed?(@open, user: @area_user)
    # store-only audience must not leak to area even when tags match
    assert_not Vazivo::KbAccess.allowed?(@express_only, user: @area_user)
    assert_not Vazivo::KbAccess.allowed?(@hq_role, user: @area_user)

    ids = Vazivo::KbAccess.apply(@tenant.kb_articles.published, user: @area_user).pluck(:id)
    assert_includes ids, @flagship_only.id
    assert_includes ids, @open.id
    assert_not_includes ids, @express_only.id
    assert_not_includes ids, @hq_role.id
  end

  test "hq bypasses role and store-tag filters" do
    assert Vazivo::KbAccess.allowed?(@hq_role, user: @brand.hq)
    assert Vazivo::KbAccess.allowed?(@flagship_only, user: @brand.hq)

    ids = Vazivo::KbAccess.apply(@tenant.kb_articles.published, user: @brand.hq).pluck(:id)
    assert_equal @tenant.kb_articles.published.pluck(:id).sort, ids.sort
  end

  test "access rules are tenant scoped" do
    other = build_brand("kb-access-other", features: { morocco_ops: true, knowledge_base: true })
    other.store.update!(store_format: "express", cluster_key: "casa-south")
    other_cat = other.tenant.kb_categories.create!(title_fr: "Other")
    foreign = other.tenant.kb_articles.create!(
      kb_category: other_cat,
      title_fr: "Secret express",
      body_fr: "Leak?",
      author: other.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store],
      audience_store_tags: %w[express]
    )

    ids = Vazivo::KbAccess.apply(@tenant.kb_articles.published, user: @brand.store_user).pluck(:id)
    assert_not_includes ids, foreign.id
    assert_equal other.tenant.id, foreign.tenant_id
  end

  test "store_tags_for reads format and cluster" do
    assert_equal %w[casa-south express], Vazivo::KbAccess.store_tags_for(@brand.store).sort
    assert_equal [], Vazivo::KbAccess.store_tags_for(nil)
  end
end
