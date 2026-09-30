require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SCREEN_SIZE = [ 1400, 1000 ].freeze

  # Chrome's save-password / leaked-password dialogs steal focus after the login form
  # (the test password is "password"), so later clicks and keystrokes never reach the page.
  def self.quiet_chrome(chrome)
    chrome.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
    chrome.add_preference(:credentials_enable_service, false)
    chrome.add_preference(:profile, password_manager_enabled: false, password_manager_leak_detection: false)
  end

  # Locally (Docker) point at a selenium/standalone-chromium container;
  # on CI the runner's own headless Chrome is used.
  if ENV["SELENIUM_REMOTE_URL"].present?
    Capybara.server_host = "0.0.0.0"
    Capybara.server_port = ENV.fetch("CAPYBARA_SERVER_PORT", 3100).to_i
    Capybara.app_host = "http://#{ENV.fetch('CAPYBARA_APP_HOST') { Socket.gethostname }}:#{Capybara.server_port}"

    driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE,
              options: { browser: :remote, url: ENV["SELENIUM_REMOTE_URL"] } do |chrome|
      # crypto.randomUUID and service workers need a secure context; the app host is plain http here
      chrome.add_argument("--unsafely-treat-insecure-origin-as-secure=#{Capybara.app_host}")
      quiet_chrome(chrome)
    end

    setup do
      # Upload local fixture files to the remote browser
      page.driver.browser.file_detector = ->(args) { args.first.to_s if File.exist?(args.first.to_s) }
    end
  else
    driven_by :selenium, using: :headless_chrome, screen_size: SCREEN_SIZE do |chrome|
      # Chrome refuses to start as root (e.g. inside a Docker container) without this
      chrome.add_argument("--no-sandbox") if Process.uid.zero?
      chrome.add_option("goog:loggingPrefs", { browser: "ALL" })
      quiet_chrome(chrome)
    end

    # Surface browser console output next to the failure screenshot
    teardown do
      next if passed?

      page.driver.browser.logs.get(:browser).each { |entry| puts "[browser #{entry.level}] #{entry.message}" }
    rescue StandardError => e
      puts "[browser logs unavailable: #{e.class}]"
    end
  end

  private

  def log_in_as(user, tenant = user.tenant)
    visit login_path
    within "#password-login-form" do
      fill_in "tenant_slug", with: tenant.slug
      fill_in "email", with: user.email
      fill_in "password", with: "password"
      click_button I18n.t("auth.sign_in", locale: :fr)
    end
    assert_current_path app_root_path
  end

  def log_out
    find("form.app-topbar-btn-form button.app-topbar-btn").click
    assert_current_path login_path
  end

  # Alpine and web fonts load from CDNs; typing or clicking before the page settles
  # gets wiped by x-model, lands on a shifting layout, or falls through to a native submit.
  def wait_for_alpine(timeout: 10)
    ready = <<~JS
      document.readyState === "complete" &&
        document.fonts.status === "loaded" &&
        Boolean(window.Alpine) &&
        [...document.querySelectorAll("[x-data]")].every((el) => el._x_dataStack)
    JS
    deadline = Time.current + timeout
    until page.evaluate_script(ready)
      flunk "Alpine did not initialise within #{timeout}s" if Time.current > deadline
      sleep 0.05
    end
  end
end
