require "test_helper"

class CommunityTest < ActiveSupport::TestCase
  test "community validates region and content cannot bypass audience" do
    brand = build_brand("community-model")
    group = brand.tenant.communities.new(title_fr: "Discussion", org_unit: brand.store)
    assert_not group.valid?
    group.org_unit = brand.region
    group.save!
    assert_not group.community_posts.new(user: brand.store_user, body: " ").valid?
    assert_not group.community_posts.new(user: brand.store_user, body: "x" * 2001).valid?
    foreign = build_brand("community-model-foreign")
    assert_not group.community_posts.new(user: foreign.hq, body: "Cross tenant").valid?
    post = group.community_posts.create!(user: brand.store_user, body: "Shared")
    assert_not post.community_comments.new(user: foreign.store_user, body: "Foreign").valid?
    assert_not post.community_comments.new(user: brand.store_user, body: "x" * 1001).valid?
    group.reload.update!(audience_role: "area")
    assert_not post.community_comments.new(user: brand.store_user, body: "Role changed").valid?
    assert_equal "Discussion", group.title
  end
end
