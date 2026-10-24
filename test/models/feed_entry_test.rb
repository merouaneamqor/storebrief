require "test_helper"

class FeedEntryTest < ActiveSupport::TestCase
  test "entry rejects cross tenant authors and non news or unsent deliveries" do
    brand = build_brand("feed-model")
    other = build_brand("feed-other")
    news = brand.tenant.communications.create!(author: brand.hq, title_fr: "News", body_fr: "News", format: "news", status: "draft")
    news.send_to!([ brand.store.id ])
    entry = FeedComment.new(tenant: brand.tenant, user: other.store_user, subject: news.deliveries.first, body: "Spoof")
    assert_not entry.valid?
    entry.user = brand.store_user
    assert entry.valid?
    news.update!(status: "draft")
    assert_not entry.valid?
    news.update!(status: "sent", format: "task")
    assert_not entry.valid?
  end

  test "store post cannot use another store or a management author" do
    brand = build_brand("feed-post-model")
    other = brand.tenant.org_units.create!(name: "Other", unit_type: "store", parent: brand.region)
    post = FeedPost.new(tenant: brand.tenant, org_unit: other, user: brand.store_user, body: "Wrong store")
    assert_not post.valid?
    post.org_unit = brand.store
    post.user = brand.hq
    assert_not post.valid?
  end
end
