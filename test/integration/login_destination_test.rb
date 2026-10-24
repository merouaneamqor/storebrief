require "test_helper"

class LoginDestinationTest < ActionDispatch::IntegrationTest
  include OidcHelpers

  setup do
    host! "localhost"
    @brand = build_brand("login-destination")
  end

  test "a signed out store user resumes the requested page after correcting a password" do
    destination = my_tasks_path(filter: "today", locale: "ar")
    get destination
    assert_redirected_to login_path
    post login_path, params: credentials.merge(password: "wrong")
    assert_response :unprocessable_entity
    post login_path, params: credentials
    assert_redirected_to destination
    follow_redirect!
    assert_response :success
    assert_select "html[dir=rtl]"
  end

  test "login ignores a supplied external return parameter" do
    get login_path(return_to: "https://example.com/phishing")
    post login_path, params: credentials.merge(return_to: "//example.com/phishing")
    assert_redirected_to app_root_path
  end

  test "unauthenticated writes are never replayed after login" do
    post complete_inbox_path(123), params: { notes: "must not be submitted" }
    assert_redirected_to login_path
    post login_path, params: credentials
    assert_redirected_to app_root_path
  end

  test "the pending page is consumed and not reused after logout" do
    get my_tasks_path
    post login_path, params: credentials
    assert_redirected_to my_tasks_path
    delete logout_path
    post login_path, params: credentials
    assert_redirected_to app_root_path
  end

  test "a large request URL does not overflow the login cookie" do
    get my_tasks_path(filter: "x" * 3000)
    assert_redirected_to login_path
    post login_path, params: credentials
    assert_redirected_to app_root_path
  end

  test "a background JSON request does not replace the intended page" do
    destination = my_tasks_path(filter: "today")
    get destination
    get offline_context_path, as: :json
    assert_redirected_to login_path
    post login_path, params: credentials
    assert_redirected_to destination
  end

  test "a remembered page is not carried across hosts" do
    get my_tasks_path
    cookie = response.headers.fetch("Set-Cookie").split(";").first
    host! "#{@brand.tenant.slug}.localhost"
    post login_path, params: credentials, headers: { "Cookie" => cookie }
    assert_redirected_to app_root_path
  end

  test "the restored page still requires the authenticated role" do
    get reports_path
    assert_redirected_to login_path
    post login_path, params: credentials
    assert_redirected_to reports_path
    follow_redirect!
    assert_redirected_to app_root_path
  end

  test "a stored task from another tenant cannot be read after login" do
    other = build_brand("destination-other")
    task = other.tenant.communications.create!(author: other.hq, title_fr: "Private other task", body_fr: "Private instructions", format: "task", status: "draft")
    task.send_to!([ other.store.id ])
    destination = my_task_path(task.deliveries.sole, kind: "task")
    get destination
    post login_path, params: credentials
    assert_redirected_to destination
    follow_redirect!
    assert_redirected_to my_tasks_path
    assert_not_includes response.body, task.title_fr
  end

  test "OIDC rotation and a failed verified callback preserve the original page for retry" do
    setting = configure_oidc(@brand.tenant)
    destination = my_tasks_path(filter: "overdue")
    get destination
    flow = start_oidc(setting)
    complete_oidc(setting, flow, claims: { nonce: "incorrect" })
    assert_nil session[:user_id]
    assert_redirected_to login_path(tenant_slug: @brand.tenant.slug)
    flow = start_oidc(setting)
    complete_oidc(setting, flow)
    assert_redirected_to destination
    follow_redirect!
    assert_response :success
  end

  test "verified SAML login resumes the pending page" do
    @brand.tenant.update!(feature_saml_sso: true)
    @brand.tenant.create_saml_setting!(enabled: true, idp_entity_id: "https://idp.example.com/saml",
      idp_sso_target_url: "https://idp.example.com/sso", idp_cert: "-----BEGIN CERTIFICATE-----\nTEST\n-----END CERTIFICATE-----")
    get my_tasks_path
    saml_response = Minitest::Mock.new
    saml_response.expect(:is_valid?, true)
    saml_response.expect(:attributes, {})
    saml_response.expect(:nameid, @brand.store_user.email)
    OneLogin::RubySaml::Response.stub(:new, saml_response) do
      post saml_acs_path(@brand.tenant.slug), params: { SAMLResponse: "verified-by-stub" }
    end
    assert_redirected_to my_tasks_path
    saml_response.verify
  end

  private

  def credentials
    { tenant_slug: @brand.tenant.slug, email: @brand.store_user.email, password: "password" }
  end
end
