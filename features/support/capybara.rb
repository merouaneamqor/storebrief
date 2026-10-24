require "capybara/cucumber"

# Mirrors test/application_system_test_case.rb: a remote Chromium when SELENIUM_REMOTE_URL is set
# (local Docker), the runner's own headless Chrome otherwise (CI).
Capybara.register_driver :cucumber_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=1400,1000")
  options.add_argument("--no-sandbox") if Process.uid.zero?
  options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
  options.add_preference(:credentials_enable_service, false)

  if ENV["SELENIUM_REMOTE_URL"].present?
    options.add_argument("--unsafely-treat-insecure-origin-as-secure=#{Capybara.app_host}")
    Capybara::Selenium::Driver.new(app, browser: :remote, url: ENV["SELENIUM_REMOTE_URL"], options: options)
  else
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end
end

if ENV["SELENIUM_REMOTE_URL"].present?
  Capybara.server_host = "0.0.0.0"
  Capybara.server_port = ENV.fetch("CAPYBARA_SERVER_PORT", 3100).to_i
  Capybara.app_host = "http://#{ENV.fetch('CAPYBARA_APP_HOST') { Socket.gethostname }}:#{Capybara.server_port}"
end

Capybara.javascript_driver = :cucumber_chrome
