require "test_helper"

class CommunitiesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("communities", features: { communities: true, morocco_ops: true })
    @group = @brand.tenant.communities.create!(title_fr: "Équipe Casa", title_ar: "فريق الدار البيضاء", org_unit: @brand.region, audience_role: "store")
    @other_region = @brand.tenant.org_units.create!(name: "Rabat", unit_type: "region")
    @other_store = @brand.tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: @other_region)
    @other_user = create_user(@brand.tenant, org_unit: @other_store, role: :store, email: "other@test.test")
    sign_in @brand.store_user
  end

  test "HQ creates explicit audiences and store discussions create no paid notifications" do
    assert_no_difference "Community.count" do
      post communities_path, params: { community: { title_fr: "Unauthorized" } }
      assert_response :forbidden
    end
    sign_in @brand.hq
    assert_difference "Community.count" do
      post communities_path, params: { community: { title_fr: "Réseau", org_unit_id: @brand.region.id, audience_role: "store" } }
      assert_redirected_to community_path(Community.last)
    end
    sign_in @brand.store_user
    assert_no_difference "NotificationLog.count" do
      assert_difference "CommunityPost.count" do
        post create_post_community_path(@group), params: { body: "Bonjour réseau" }
      end
      assert_difference "CommunityComment.count" do
        post create_comment_community_path(@group), params: { post_id: CommunityPost.last.id, body: "Merci" }
      end
    end
    assert_equal 0, DeliveryComment.count
    assert_equal 0, FeedComment.count
    get community_path(@group)
    assert_response :success
    assert_select "p", text: "Bonjour réseau"
    assert_select "p", text: "Merci"
  end

  test "regional sharing is explicit while role and tenant boundaries deny direct IDs" do
    peer = @brand.tenant.org_units.create!(name: "Ain Sebaa", unit_type: "store", parent: @brand.region)
    peer_user = create_user(@brand.tenant, org_unit: peer, role: :store, email: "peer@test.test")
    sign_in peer_user
    get community_path(@group)
    assert_response :success
    [ @other_user, create_user(@brand.tenant, org_unit: @brand.region, role: :area) ].each do |user|
      sign_in user
      get communities_path
      assert_select "a[href='#{community_path(@group)}']", count: 0
      get community_path(@group)
      assert_response :not_found
      post create_post_community_path(@group), params: { body: "Leak" }
      assert_response :not_found
    end
    foreign = build_brand("foreign-community", features: { communities: true })
    foreign_group = foreign.tenant.communities.create!(title_fr: "Foreign")
    sign_in @brand.hq
    get community_path(foreign_group)
    assert_response :not_found
    assert_no_difference "Community.count" do
      post communities_path, params: { community: { title_fr: "Foreign region", org_unit_id: foreign.region.id } }
      assert_response :not_found
    end
  end

  test "moderation is bounded to community and requires capability" do
    post create_post_community_path(@group), params: { body: "Remove me" }
    entry = CommunityPost.last
    post create_comment_community_path(@group), params: { post_id: entry.id, body: "Reply" }
    comment = CommunityComment.last
    delete destroy_post_community_path(@group, post_id: entry.id)
    assert_response :forbidden
    delete community_path(@group)
    assert_response :forbidden
    sign_in @brand.hq
    second = @brand.tenant.communities.create!(title_fr: "Second")
    delete destroy_post_community_path(second, post_id: entry.id)
    assert_response :not_found
    delete destroy_comment_community_path(@group, post_id: entry.id, comment_id: comment.id)
    assert_not CommunityComment.exists?(comment.id)
    delete destroy_post_community_path(@group, post_id: entry.id)
    assert_not CommunityPost.exists?(entry.id)
    delete community_path(@group)
    assert_not Community.exists?(@group.id)
  end

  test "custom membership must supply capability and scope together" do
    role = @brand.tenant.tenant_roles.create!(name: "No community", base_role: "store", capabilities: [ "inbox" ])
    @brand.store_user.memberships.first.update!(tenant_role: role)
    @brand.store_user.memberships.create!(org_unit: @other_store, role: "store")
    get community_path(@group)
    assert_response :not_found
    role.update!(capabilities: [ "communities" ])
    get community_path(@group)
    assert_response :success
    restricted = @brand.tenant.tenant_roles.create!(name: "Regional moderator", base_role: "hq", capabilities: [ "manage_communities" ])
    @brand.hq.memberships.first.update!(tenant_role: restricted)
    sign_in @brand.hq
    get community_path(@group)
    assert_response :success
    elsewhere = @brand.tenant.communities.create!(title_fr: "Elsewhere", org_unit: @other_region)
    get community_path(elsewhere)
    assert_response :not_found
    assert_no_difference "Community.count" do
      post communities_path, params: { community: { title_fr: "Network wide" } }
      assert_response :forbidden
    end
  end

  test "posts paginate and removed moderation capability cannot destroy discussion" do
    21.times { |index| @group.community_posts.create!(user: @brand.store_user, body: "Message #{index}") }
    get community_path(@group)
    assert_select "article", count: 20
    get community_path(@group, page: 2)
    assert_select "article", count: 1
    role = @brand.tenant.tenant_roles.create!(name: "HQ participant", base_role: "hq", capabilities: [ "communities" ])
    @brand.hq.memberships.first.update!(tenant_role: role)
    sign_in @brand.hq
    all_roles = @brand.tenant.communities.create!(title_fr: "Everyone")
    assert_no_difference "Community.count" do
      delete community_path(all_roles)
      assert_response :forbidden
    end
  end

  test "feature gates and four locales with RTL render" do
    %w[fr ar en es].each do |locale|
      get communities_path(locale: locale)
      assert_response :success
      assert_match I18n.t("communities.title", locale: locale), response.body
      get community_path(@group, locale: locale)
      assert_response :success
      assert_select "html[dir='rtl']" if locale == "ar"
    end
    @brand.tenant.update!(feature_communities: false)
    get community_path(@group)
    assert_redirected_to app_root_path
    @brand.tenant.update!(feature_communities: true, feature_morocco_ops: false)
    post create_post_community_path(@group), params: { body: "Disabled" }
    assert_redirected_to app_root_path
  end
end
