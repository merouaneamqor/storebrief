require "test_helper"

class FeedEngagementTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("feed-engagement", features: { morocco_ops: true, briefs: true, push_alerts: false })
    @news = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "Company news", body_fr: "News", format: "news", status: "draft")
    @news.send_to!([ @brand.store.id ])
    @delivery = @news.deliveries.first
    sign_in @brand.store_user
  end

  test "store comments and changes one reaction with no paid alerts" do
    assert_no_difference "NotificationLog.count" do
      assert_difference "FeedComment.count" do
        post feed_comments_path, params: subject_params.merge(body: "Useful update")
        assert_redirected_to newsfeeds_path
      end
      assert_difference "FeedReaction.count" do
        post feed_reactions_path, params: subject_params.merge(kind: "helpful")
      end
      assert_no_difference "FeedReaction.count" do
        post feed_reactions_path, params: subject_params.merge(kind: "thanks")
      end
    end
    assert_equal "thanks", FeedReaction.last.kind
    get newsfeeds_path
    assert_select "p", text: /Useful update/
    delete feed_reaction_path(FeedReaction.last)
    assert_equal 0, FeedReaction.count
    assert_no_difference "FeedReaction.count" do
      post feed_reactions_path, params: subject_params.merge(kind: "unknown")
    end
  end

  test "posts require HQ approval and can be removed with comments" do
    post feed_posts_path, params: { body: "Our store update" }
    item = FeedPost.last
    assert_equal "pending", item.status
    post feed_comments_path, params: { subject_type: "FeedPost", subject_id: item.id, body: "Premature" }
    assert_response :not_found
    post publish_feed_post_path(item)
    assert_redirected_to app_root_path
    sign_in @brand.hq
    post publish_feed_post_path(item)
    assert_equal "published", item.reload.status
    sign_in @brand.store_user
    post feed_comments_path, params: { subject_type: "FeedPost", subject_id: item.id, body: "Store comment" }
    comment = FeedComment.last
    delete feed_comment_path(comment)
    assert_nil comment.reload.removed_at
    sign_in @brand.hq
    get feed_moderation_path
    assert_response :success
    assert_match "Store comment", response.body
    delete feed_comment_path(comment)
    assert comment.reload.removed_at
    delete feed_post_path(item)
    assert_equal "removed", item.reload.status
    sign_in @brand.store_user
    get newsfeeds_path
    assert_no_match "Our store update", response.body
    assert_equal 0, DeliveryComment.count
  end

  test "other stores tenants drafts tasks area and feature flags cannot engage" do
    other_store = @brand.tenant.org_units.create!(name: "Other", unit_type: "store", parent: @brand.region)
    @news.send_to!([ other_store.id ])
    other_delivery = @news.deliveries.find_by!(org_unit: other_store)
    assert_no_difference "FeedComment.count" do
      post feed_comments_path, params: { subject_type: "Delivery", subject_id: other_delivery.id, body: "Leak" }
      assert_response :not_found
      post feed_comments_path, params: { subject_type: "User", subject_id: @brand.hq.id, body: "Leak" }
      assert_response :not_found
    end
    foreign = build_brand("foreign-feed", features: { morocco_ops: true, briefs: true })
    foreign_post = FeedPost.create!(tenant: foreign.tenant, user: foreign.store_user, org_unit: foreign.store, body: "Secret", status: "published")
    post feed_comments_path, params: { subject_type: "FeedPost", subject_id: foreign_post.id, body: "Leak" }
    assert_response :not_found
    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    sign_in area
    post feed_posts_path, params: { body: "Area post" }
    assert_redirected_to app_root_path
    get feed_moderation_path
    assert_redirected_to app_root_path
    sign_in @brand.store_user
    @brand.tenant.update!(features: @brand.tenant.features.merge("briefs" => false))
    post feed_comments_path, params: subject_params.merge(body: "Disabled")
    assert_redirected_to app_root_path
  end

  test "locales render discussion in French Arabic and Spanish" do
    %w[fr ar es].each do |locale|
      get newsfeeds_path(locale: locale)
      assert_response :success
      assert_match I18n.t("feed_engagement.helpful", locale: locale), response.body
    end
  end

  private

  def subject_params
    { subject_type: "Delivery", subject_id: @delivery.id }
  end
end
