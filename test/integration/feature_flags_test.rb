require "test_helper"

class FeatureFlagsTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "all hq nav links show with default flags" do
    brand = build_brand("flags-default")
    sign_in(brand.hq)

    assert_select "a.app-nav-link[href=?]", app_root_path
    assert_select "a.app-nav-link[href=?]", communications_path
    assert_select "a.app-nav-link[href=?]", playbooks_path
    assert_select "a.app-nav-link[href=?]", ranking_path
    assert_select "a.app-nav-link[href=?]", new_communication_path
    assert_select "details.app-nav-more a.app-nav-link[href=?]", checklists_path
    assert_select "details.app-nav-more a.app-nav-link[href=?]", templates_path
    assert_select "details.app-nav-more a.app-nav-link[href=?]", reports_path
  end

  test "store morocco nav is today and ranking only" do
    brand = build_brand("flags-store-nav")
    sign_in(brand.store_user)

    assert_select "a.app-nav-link[href=?]", app_root_path
    assert_select "a.app-nav-link[href=?]", ranking_path
    assert_select "a.app-nav-link[href=?]", inbox_index_path, count: 0
    assert_select "a.app-nav-link[href=?]", checklists_deliveries_path, count: 0
  end

  test "briefs off hides compose and blocks brief routes for hq and stores" do
    brand = build_brand("flags-briefs", features: { briefs: false })

    sign_in(brand.hq)
    assert_select "a.app-nav-link[href=?]", communications_path, count: 0
    assert_select "a.app-nav-link[href=?]", new_communication_path, count: 0
    assert_feature_blocked communications_path
    assert_feature_blocked new_communication_path

    sign_in(brand.store_user)
    assert_select "a.app-nav-link[href=?]", inbox_index_path, count: 0
    assert_feature_blocked inbox_index_path
  end

  test "checklists off hides checklists and templates for hq and stores" do
    brand = build_brand("flags-checklists", features: { checklists: false })

    sign_in(brand.hq)
    assert_select "a.app-nav-link[href=?]", checklists_path, count: 0
    assert_select "a.app-nav-link[href=?]", templates_path, count: 0
    assert_feature_blocked checklists_path
    assert_feature_blocked templates_path

    sign_in(brand.store_user)
    assert_select "a.app-nav-link[href=?]", checklists_deliveries_path, count: 0
    assert_feature_blocked checklists_deliveries_path
  end

  test "reports off hides and blocks reports" do
    brand = build_brand("flags-reports", features: { reports: false })
    sign_in(brand.hq)

    assert_select "a.app-nav-link[href=?]", reports_path, count: 0
    assert_feature_blocked reports_path
  end

  test "offline checklists off blocks the sync endpoint" do
    brand = build_brand("flags-offline", features: { offline_checklists: false })
    sign_in(brand.store_user)

    post sync_checklist_responses_path, as: :json, params: { responses: [] }
    assert_redirected_to app_root_path
  end

  private

  def assert_feature_blocked(path)
    get path
    assert_redirected_to app_root_path, "expected #{path} to be gated"
    assert_equal I18n.t("auth.feature_disabled", locale: :en), flash[:alert]
  end
end
