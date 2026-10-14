require "test_helper"

class KbArticleTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("kb-art", features: { morocco_ops: true, knowledge_base: true })
    @tenant = @brand.tenant
    @category = @tenant.kb_categories.create!(title_fr: "Process")
  end

  def build_article(**attrs)
    @tenant.kb_articles.create!({
      kb_category: @category,
      title_fr: "Ouverture magasin",
      title_ar: "فتح المتجر",
      body_fr: "Checklist d'ouverture.",
      body_ar: "قائمة الفتح.",
      author: @brand.hq
    }.merge(attrs))
  end

  test "defaults to draft version 1 and requires french body" do
    article = build_article
    assert article.draft?
    assert_equal 1, article.version
    assert_equal "Ouverture magasin", article.title

    blank = @tenant.kb_articles.new(kb_category: @category, title_fr: "X", body_fr: "")
    assert_not blank.valid?
  end

  test "publish creates a version snapshot and republish bumps version" do
    article = build_article
    article.publish!(by: @brand.hq)

    assert article.published?
    assert_equal 1, article.version
    assert_equal 1, article.kb_article_versions.count
    assert_equal "Ouverture magasin", article.kb_article_versions.first.title_fr

    article.update!(body_fr: "Checklist d'ouverture mise a jour.")
    article.publish!(by: @brand.hq)

    assert_equal 2, article.version
    assert_equal 2, article.kb_article_versions.count
    assert_equal "Checklist d'ouverture mise a jour.", article.kb_article_versions.newest_first.first.body_fr
  end

  test "archive and unpublish change publish state" do
    article = build_article
    article.publish!
    article.archive!
    assert article.archived?

    article.unpublish!
    assert article.draft?
  end

  test "rejects category from another tenant" do
    other = build_brand("kb-art-other", features: { morocco_ops: true, knowledge_base: true })
    foreign = other.tenant.kb_categories.create!(title_fr: "Other")

    article = @tenant.kb_articles.new(
      kb_category: foreign,
      title_fr: "Leak",
      body_fr: "Should fail"
    )
    assert_not article.valid?
    assert_predicate article.errors[:kb_category], :any?
  end

  test "localized_value prefers arabic when locale is ar" do
    article = build_article
    I18n.with_locale(:ar) do
      assert_equal "فتح المتجر", article.title
      assert_equal "قائمة الفتح.", article.body
    end
  end

  test "normalizes audience store tags and combines with role access" do
    article = build_article(audience_roles: %w[store], audience_store_tags: [ " express ", "flagship,casa-center", "" ])
    assert_equal %w[casa-center express flagship], article.audience_store_tags.sort

    assert article.accessible_to?(role: "store", store_tags: %w[express])
    assert_not article.accessible_to?(role: "hq", store_tags: %w[express])
    assert_not article.accessible_to?(role: "store", store_tags: %w[mall])
    assert article.accessible_to?(role: "store", store_tags: %w[mall casa-center])
  end
end
