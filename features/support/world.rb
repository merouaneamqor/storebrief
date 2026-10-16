# Reuse the builders the Minitest suite already relies on (tenants, org tree, users).
require Rails.root.join("test/support/tenant_helpers")

module UiWorld
  include TenantHelpers
  include Rails.application.routes.url_helpers

  PAGES = {
    "visits" => :visits_path,
    "vm missions" => :vm_missions_path,
    "playbooks" => :playbooks_path,
    "briefs" => :communications_path,
    "knowledge base" => :kb_articles_path,
    "inbox" => :inbox_index_path,
    "reports" => :reports_path
  }.freeze

  def page_path(name)
    helper = PAGES.fetch(name) { raise ArgumentError, "Unknown page #{name.inspect}; add it to UiWorld::PAGES" }
    public_send(helper)
  end

  def log_in(user)
    visit login_path
    within "#password-login-form" do
      fill_in "tenant_slug", with: user.tenant.slug
      fill_in "email", with: user.email
      fill_in "password", with: "password"
      click_button I18n.t("auth.sign_in", locale: :fr)
    end
    page.assert_current_path(app_root_path)
  end
end

World(UiWorld)
