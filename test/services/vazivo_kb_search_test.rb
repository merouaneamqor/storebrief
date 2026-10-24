require "test_helper"

class VazivoKbSearchTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("kb-search-svc", features: { morocco_ops: true, knowledge_base: true })
    @tenant = @brand.tenant
    @category = @tenant.kb_categories.create!(title_fr: "SOP")
  end

  test "ranks title matches above body-only matches" do
    body_hit = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Procedure generale",
      body_fr: "Inclut le mot caisse a la fin.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current
    )
    title_hit = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Ouverture caisse",
      body_fr: "Etapes du matin.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current
    )
    @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Dress code",
      body_fr: "Uniforme requis.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current
    )

    result = Vazivo::KbSearch.call(tenant: @tenant, query: "caisse", role: nil, published_only: true)
    ids = result.articles.map(&:id)

    assert_equal [ title_hit.id, body_hit.id ], ids
    assert result.articles.first.search_rank.to_f >= result.articles.second.search_rank.to_f
  end

  test "filters by audience role and excludes drafts for published_only" do
    open_article = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Ouverture magasin",
      body_fr: "Checklist.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: []
    )
    store_only = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Conseil magasin",
      body_fr: "Tips magasin.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store]
    )
    hq_only = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Note siege",
      body_fr: "Interne HQ.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[hq]
    )
    @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Brouillon magasin",
      body_fr: "Pas encore.",
      author: @brand.hq,
      publish_state: "draft",
      audience_roles: %w[store]
    )

    store_ids = Vazivo::KbSearch.call(tenant: @tenant, query: nil, role: "store", published_only: true).articles.map(&:id)
    assert_includes store_ids, open_article.id
    assert_includes store_ids, store_only.id
    assert_not_includes store_ids, hq_only.id

    hq_ids = Vazivo::KbSearch.call(tenant: @tenant, query: nil, role: "hq", published_only: true).articles.map(&:id)
    assert_includes hq_ids, open_article.id
    assert_includes hq_ids, hq_only.id
    assert_not_includes hq_ids, store_only.id
  end

  test "search is tenant scoped" do
    other = build_brand("kb-search-other", features: { morocco_ops: true, knowledge_base: true })
    other_cat = other.tenant.kb_categories.create!(title_fr: "Other")
    other.tenant.kb_articles.create!(
      kb_category: other_cat,
      title_fr: "Secret caisse",
      body_fr: "Autre tenant.",
      author: other.hq,
      publish_state: "published",
      published_at: Time.current
    )
    mine = @tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Caisse locale",
      body_fr: "Chez nous.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current
    )

    ids = Vazivo::KbSearch.call(tenant: @tenant, query: "caisse", published_only: true).articles.map(&:id)
    assert_equal [ mine.id ], ids
  end
end
