require "test_helper"

class KbAccessTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("kb-access-ui", features: { morocco_ops: true, knowledge_base: true })
    @brand.store.update!(store_format: "express", cluster_key: "casa-south")
    @category = @brand.tenant.kb_categories.create!(title_fr: "SOP")

    @open = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Procedure ouverte",
      body_fr: "Tous magasins.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: [],
      audience_store_tags: []
    )
    @hq_only = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Document interne",
      body_fr: "Siege seulement.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[hq],
      audience_store_tags: []
    )
    @express = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Guide express",
      body_fr: "Pour express.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store],
      audience_store_tags: %w[express]
    )
    @flagship = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Guide flagship",
      body_fr: "Pour flagship.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store],
      audience_store_tags: %w[flagship]
    )
  end

  test "store user list and show enforce role and store-tag access without leakage" do
    sign_in(@brand.store_user)

    get kb_articles_path
    assert_response :success
    assert_match "Procedure ouverte", response.body
    assert_match "Guide express", response.body
    assert_no_match "Document interne", response.body
    assert_no_match "Guide flagship", response.body

    get kb_article_path(@open)
    assert_response :success

    get kb_article_path(@express)
    assert_response :success

    get kb_article_path(@hq_only)
    assert_redirected_to kb_articles_path

    get kb_article_path(@flagship)
    assert_redirected_to kb_articles_path
  end

  test "store user search does not leak wrong-tag or hq-only articles" do
    sign_in(@brand.store_user)

    get kb_articles_path, params: { q: "Guide" }
    assert_response :success
    assert_match "Guide express", response.body
    assert_no_match "Guide flagship", response.body
    assert_no_match "Document interne", response.body
  end

  test "hq can set store tags and still open restricted articles" do
    sign_in(@brand.hq)

    assert_difference -> { @brand.tenant.kb_articles.count }, 1 do
      post kb_articles_path, params: {
        kb_article: {
          kb_category_id: @category.id,
          title_fr: "Cluster casa-south",
          body_fr: "Tag cible.",
          publish_state: "published",
          audience_roles: %w[store],
          audience_store_tags: %w[casa-south]
        }
      }
    end

    article = @brand.tenant.kb_articles.order(:id).last
    assert_equal %w[casa-south], article.audience_store_tags
    assert_redirected_to kb_article_path(article)

    get kb_article_path(@flagship)
    assert_response :success
    assert_match "Guide flagship", response.body
  end

  test "foreign tenant article is not readable via id" do
    other = build_brand("kb-access-leak", features: { morocco_ops: true, knowledge_base: true })
    other_cat = other.tenant.kb_categories.create!(title_fr: "X")
    foreign = other.tenant.kb_articles.create!(
      kb_category: other_cat,
      title_fr: "Secret autre tenant",
      body_fr: "Ne pas fuir.",
      author: other.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: [],
      audience_store_tags: []
    )

    sign_in(@brand.store_user)
    get kb_article_path(foreign)
    assert_response :not_found
  end
end
