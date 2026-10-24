require "test_helper"

class KbArticlesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("kb-hq", features: { morocco_ops: true, knowledge_base: true })
    @category = @brand.tenant.kb_categories.create!(title_fr: "SOP", title_ar: "إجراء")
  end

  test "hq creates publishes and archives an article" do
    sign_in(@brand.hq)

    get kb_articles_path
    assert_response :success
    assert_match(/Base de connaissances|Knowledge base/, response.body)

    assert_difference -> { @brand.tenant.kb_articles.count }, 1 do
      post kb_articles_path, params: {
        kb_article: {
          kb_category_id: @category.id,
          title_fr: "Fermeture magasin",
          title_ar: "إغلاق المتجر",
          body_fr: "Etapes de fermeture.",
          body_ar: "خطوات الإغلاق.",
          publish_state: "draft"
        }
      }
    end

    article = @brand.tenant.kb_articles.last
    assert_redirected_to kb_article_path(article)
    assert article.draft?
    assert_equal 1, article.version

    post publish_kb_article_path(article)
    assert_redirected_to kb_article_path(article)
    assert article.reload.published?
    assert_equal 1, article.kb_article_versions.count

    post archive_kb_article_path(article)
    assert article.reload.archived?
  end

  test "hq manages category tree" do
    sign_in(@brand.hq)

    get kb_categories_path
    assert_response :success

    assert_difference -> { @brand.tenant.kb_categories.count }, 1 do
      post kb_categories_path, params: {
        kb_category: {
          title_fr: "Ouverture",
          title_ar: "فتح",
          parent_id: @category.id,
          position: 0
        }
      }
    end
    child = @brand.tenant.kb_categories.order(:id).last
    assert_equal @category.id, child.parent_id

    get kb_categories_path
    assert_match "Ouverture", response.body
  end

  test "store users can browse but cannot manage kb" do
    published = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Visible store",
      body_fr: "Publie.",
      author: @brand.hq,
      publish_state: "published",
      published_at: Time.current
    )
    sign_in(@brand.store_user)

    get kb_articles_path
    assert_response :success
    assert_match "Visible store", response.body

    get new_kb_article_path
    assert_redirected_to app_root_path

    assert_no_difference -> { KbArticle.count } do
      post kb_articles_path, params: {
        kb_article: { kb_category_id: @category.id, title_fr: "Nope", body_fr: "Nope" }
      }
    end

    get kb_article_path(published)
    assert_response :success
  end

  test "morocco_ops and knowledge_base flags gate the pages" do
    off = build_brand("kb-off", features: { morocco_ops: false, knowledge_base: true })
    sign_in(off.hq)
    get kb_articles_path
    assert_redirected_to app_root_path

    kb_off = build_brand("kb-flag-off", features: { morocco_ops: true, knowledge_base: false })
    sign_in(kb_off.hq)
    get kb_articles_path
    assert_redirected_to app_root_path
  end

  test "articles are scoped to the tenant" do
    other = build_brand("kb-other", features: { morocco_ops: true, knowledge_base: true })
    foreign_cat = other.tenant.kb_categories.create!(title_fr: "Other")
    foreign = other.tenant.kb_articles.create!(
      kb_category: foreign_cat,
      title_fr: "Foreign",
      body_fr: "Secret",
      author: other.hq
    )

    sign_in(@brand.hq)
    get kb_article_path(foreign)
    assert_response :not_found
    get edit_kb_article_path(foreign)
    assert_response :not_found
  end

  test "hq can edit and delete an article" do
    article = @brand.tenant.kb_articles.create!(
      kb_category: @category,
      title_fr: "Dress code",
      body_fr: "Uniforme requis.",
      author: @brand.hq
    )
    sign_in(@brand.hq)

    patch kb_article_path(article), params: {
      kb_article: { title_fr: "Dress code magasin", body_fr: "Uniforme requis.", kb_category_id: @category.id, publish_state: "draft" }
    }
    assert_redirected_to kb_article_path(article)
    assert_equal "Dress code magasin", article.reload.title_fr

    assert_difference -> { @brand.tenant.kb_articles.count }, -1 do
      delete kb_article_path(article)
    end
    assert_redirected_to kb_articles_path
  end
end
