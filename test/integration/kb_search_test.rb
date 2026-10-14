require "test_helper"

class KbSearchTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("kb-search-ui", features: { morocco_ops: true, knowledge_base: true })
    @category = @brand.tenant.kb_categories.create!(title_fr: "SOP")
    @published = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Fermeture caisse",
      body_fr: "Compter les billets.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: []
    )
    @store_only = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Accueil client",
      body_fr: "Sourire a l'entree.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[store]
    )
    @hq_only = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Politique interne",
      body_fr: "Reserve au siege.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current,
      audience_roles: %w[hq]
    )
    @draft = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Brouillon caisse",
      body_fr: "Pas publie.",
      author: @brand.hq,
      publish_state: "draft"
    )
  end

  test "store user sees search box and published articles for their role" do
    sign_in(@brand.store_user)

    get kb_articles_path
    assert_response :success
    assert_match(/Recherche|Search|Busqueda|بحث/, response.body)
    assert_match "Fermeture caisse", response.body
    assert_match "Accueil client", response.body
    assert_no_match "Politique interne", response.body
    assert_no_match "Brouillon caisse", response.body
  end

  test "store user full-text search ranks and finds published articles" do
    sign_in(@brand.store_user)

    get kb_articles_path, params: { q: "caisse" }
    assert_response :success
    assert_match "Fermeture caisse", response.body
    assert_no_match "Brouillon caisse", response.body
    assert_no_match "Accueil client", response.body
  end

  test "store cannot manage and cannot open hq-only article" do
    sign_in(@brand.store_user)

    get kb_article_path(@hq_only)
    assert_redirected_to kb_articles_path

    get new_kb_article_path
    assert_redirected_to app_root_path

    assert_no_difference -> { KbArticle.count } do
      post kb_articles_path, params: {
        kb_article: { kb_category_id: @category.id, title_fr: "Nope", body_fr: "Nope" }
      }
    end
  end

  test "store can read a published open article" do
    sign_in(@brand.store_user)

    get kb_article_path(@published)
    assert_response :success
    assert_match "Fermeture caisse", response.body
    assert_no_match(/Modifier|Edit|Editar|تعديل/, response.body)
  end

  test "hq role filter previews store audience" do
    sign_in(@brand.hq)

    get kb_articles_path, params: { role: "store" }
    assert_response :success
    assert_match "Fermeture caisse", response.body
    assert_match "Accueil client", response.body
    assert_no_match "Politique interne", response.body
  end

  test "hq can set audience roles on create" do
    sign_in(@brand.hq)

    assert_difference -> { @brand.tenant.kb_articles.count }, 1 do
      post kb_articles_path, params: {
        kb_article: {
          kb_category_id: @category.id,
          title_fr: "Guide zone",
          body_fr: "Pour area.",
          publish_state: "published",
          audience_roles: %w[area store]
        }
      }
    end

    article = @brand.tenant.kb_articles.order(:id).last
    assert_equal %w[area store], article.audience_roles.sort
    assert article.published?
  end
end
