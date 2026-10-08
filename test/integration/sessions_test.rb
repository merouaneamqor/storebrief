require "test_helper"

class SessionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("atlas-sessions")
  end

  test "login page renders" do
    get login_path
    assert_response :success
    assert_select "form[action=?]", login_path
  end

  test "valid credentials sign in and land on the dashboard" do
    post login_path, params: { tenant_slug: @brand.tenant.slug, email: "  HQ@Atlas-Sessions.test ", password: "password" }
    assert_redirected_to app_root_path
    follow_redirect!
    assert_response :success
  end

  test "wrong password is rejected" do
    post login_path, params: { tenant_slug: @brand.tenant.slug, email: @brand.hq.email, password: "nope" }
    assert_response :unprocessable_entity
    assert_select ".flash, [role=alert], p", text: I18n.t("auth.invalid", locale: :fr)

    get app_root_path
    assert_redirected_to login_path
  end

  test "unknown brand slug is rejected" do
    post login_path, params: { tenant_slug: "nope", email: @brand.hq.email, password: "password" }
    assert_response :unprocessable_entity
  end

  test "a user cannot sign in through another brand's slug" do
    other = build_brand("contoso-sessions")

    post login_path, params: { tenant_slug: other.tenant.slug, email: @brand.hq.email, password: "password" }
    assert_response :unprocessable_entity
  end

  test "logout ends the session" do
    sign_in(@brand.hq)

    delete logout_path
    assert_redirected_to login_path

    get app_root_path
    assert_redirected_to login_path
  end

  test "another brand's credentials are rejected on a brand subdomain" do
    other = build_brand("contoso-hosts")
    host! "#{other.tenant.slug}.localhost"

    post login_path, params: { tenant_slug: @brand.tenant.slug, email: @brand.hq.email, password: "password" }
    assert_response :unprocessable_entity

    get app_root_path
    assert_redirected_to login_path
  end

  test "signing in on a brand subdomain uses that brand" do
    host! "#{@brand.tenant.slug}.localhost"

    post login_path, params: { email: @brand.store_user.email, password: "password" }
    assert_redirected_to app_root_path
    follow_redirect!
    assert_response :success
  end
end
