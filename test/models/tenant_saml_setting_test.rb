require "test_helper"

class TenantSamlSettingTest < ActiveSupport::TestCase
  test "idp sso url must be a single http(s) url" do
    setting = create_tenant("SAML Url", "saml-url").build_saml_setting

    setting.idp_sso_target_url = "https://idp.example.com/sso"
    assert setting.valid?

    [ "ftp://idp.example.com/sso", "https://idp.example.com/sso\njavascript:alert(1)", "https://" ].each do |url|
      setting.idp_sso_target_url = url
      assert_not setting.valid?, "expected #{url.inspect} to be rejected"
    end
  end
end
