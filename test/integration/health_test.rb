require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "health check is public and green" do
    host! "localhost"
    get rails_health_check_path
    assert_response :success
  end
end
