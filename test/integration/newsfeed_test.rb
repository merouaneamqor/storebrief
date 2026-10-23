require "test_helper"

class NewsfeedTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "store sees chronological news and announcements with pagination and operational discussion" do
    brand = build_brand("atlas-newsfeed", features: { morocco_ops: true, briefs: true })
    other = brand.tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: brand.region)

    older = brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Older note",
      body_fr: "First company note for the feed.",
      format: "news",
      status: "draft"
    )
    older.send_to!([ brand.store.id ])
    older.update_columns(created_at: 2.days.ago)

    newer = brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Newer announcement",
      body_fr: "Fresh announcement with details for managers.",
      format: "announcement",
      status: "draft"
    )
    newer.send_to!([ brand.store.id ])
    newer.update_columns(created_at: 1.hour.ago)

    task = brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Hidden task",
      body_fr: "Tasks stay out of the newsfeed.",
      format: "task",
      status: "draft"
    )
    task.send_to!([ brand.store.id ])

    foreign = brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Other store only",
      body_fr: "Must not leak across stores.",
      format: "news",
      status: "draft"
    )
    foreign.send_to!([ other.id ])

    draft = brand.tenant.communications.create!(
      author: brand.hq,
      title_fr: "Draft news",
      body_fr: "Still a draft.",
      format: "news",
      status: "draft"
    )

    sign_in brand.store_user

    get newsfeeds_path
    assert_response :success
    assert_select "[data-testid=newsfeed]"
    assert_select "h1", text: I18n.t("morocco.newsfeed.title", locale: :en)
    assert_select "a.app-nav-link[href=?]", newsfeeds_path

    assert_select "a", text: "Newer announcement"
    assert_select "a", text: "Older note"
    assert_select "a", text: "Hidden task", count: 0
    assert_select "a", text: "Other store only", count: 0
    assert_select "a", text: "Draft news", count: 0

    body = response.body
    assert_operator body.index("Newer announcement"), :<, body.index("Older note")

    # No follows or shares on the operational feed.
    assert_select "[data-like], .like, .share-btn, .follow", count: 0
    assert_no_match(/\b(like|follow)\b/i, body)
    assert_select ".newsfeed-pager", count: 0

    own_delivery = newer.deliveries.find_by!(org_unit: brand.store)
    assert_select "a[href=?]", inbox_path(own_delivery)

    # Force pagination with a small per_page for the store feed.
    get newsfeeds_path, params: { per_page: 1, page: 1 }
    assert_response :success
    assert_select "a", text: "Newer announcement"
    assert_select "a", text: "Older note", count: 0
    assert_select ".newsfeed-pager"
    assert_match I18n.t("morocco.newsfeed.page_status", page: 1, total: 2, locale: :en), response.body
    assert_select "a.newsfeed-pager__link[href=?]", newsfeeds_path(page: 2)

    get newsfeeds_path, params: { per_page: 1, page: 2 }
    assert_response :success
    assert_select "a", text: "Older note"
    assert_select "a", text: "Newer announcement", count: 0
    assert_select "a.newsfeed-pager__link[href=?]", newsfeeds_path(page: 1)

    assert_equal "draft", draft.reload.status
  end

  test "HQ cannot open the store newsfeed" do
    brand = build_brand("atlas-newsfeed-hq", features: { morocco_ops: true, briefs: true })
    sign_in brand.hq

    get newsfeeds_path
    assert_redirected_to app_root_path
  end

  test "morocco_ops and briefs flags gate the newsfeed" do
    brand = build_brand("atlas-newsfeed-flag", features: { morocco_ops: false, briefs: true })
    sign_in brand.store_user

    get newsfeeds_path
    assert_redirected_to app_root_path

    brand.tenant.update!(features: brand.tenant.features.merge("morocco_ops" => true, "briefs" => false))
    get newsfeeds_path
    assert_redirected_to app_root_path
  end

  test "empty feed shows a quiet empty state" do
    brand = build_brand("atlas-newsfeed-empty", features: { morocco_ops: true, briefs: true })
    sign_in brand.store_user

    get newsfeeds_path
    assert_response :success
    assert_select ".empty", text: I18n.t("morocco.newsfeed.empty", locale: :en)
  end
end
