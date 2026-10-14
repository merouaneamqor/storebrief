require "test_helper"

class KbCategoryTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("kb-cat", features: { morocco_ops: true, knowledge_base: true })
    @tenant = @brand.tenant
  end

  test "builds a category tree with ordered children" do
    root = @tenant.kb_categories.create!(title_fr: "SOP", title_ar: "إجراء", position: 0)
    child_b = @tenant.kb_categories.create!(title_fr: "Ouverture", parent: root, position: 1)
    child_a = @tenant.kb_categories.create!(title_fr: "Fermeture", parent: root, position: 0)

    tree = KbCategory.tree_for(@tenant)
    assert_equal [ root, child_a, child_b ], tree.map(&:first)
    assert_equal [ 0, 1, 1 ], tree.map(&:last)
  end

  test "rejects parent from another tenant" do
    other = build_brand("kb-cat-other", features: { morocco_ops: true, knowledge_base: true })
    foreign = other.tenant.kb_categories.create!(title_fr: "Foreign")

    category = @tenant.kb_categories.new(title_fr: "Local", parent: foreign)
    assert_not category.valid?
    assert_predicate category.errors[:parent], :any?
  end

  test "rejects cyclic parent assignment" do
    root = @tenant.kb_categories.create!(title_fr: "Root")
    child = @tenant.kb_categories.create!(title_fr: "Child", parent: root)

    root.parent = child
    assert_not root.valid?
    assert_predicate root.errors[:parent], :any?
  end

  test "restricts destroy when articles exist" do
    category = @tenant.kb_categories.create!(title_fr: "Policies")
    @tenant.kb_articles.create!(
      kb_category: category,
      title_fr: "Dress code",
      body_fr: "Wear the brand uniform.",
      author: @brand.hq
    )

    assert_not category.destroy
    assert category.persisted?
  end
end
