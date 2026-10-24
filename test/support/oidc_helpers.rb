require "jwt"

module OidcHelpers
  KEY = OpenSSL::PKey::RSA.generate(2048)
  JWK = JWT::JWK.new(KEY)

  def configure_oidc(tenant, **attributes)
    tenant.update!(feature_oidc_sso: true)
    tenant.create_oidc_setting!({ enabled: true, jit_enabled: true, issuer: "https://idp.example.com",
      client_id: "vazivo-client", client_secret: "private-client-secret",
      authorization_endpoint: "https://idp.example.com/authorize", token_endpoint: "https://idp.example.com/token",
      jwks_uri: "https://idp.example.com/keys",
      role_mappings: [ { "claim" => "groups", "value" => "store-team", "role" => "store", "org_unit_id" => tenant.org_units.stores.first.id } ] }.merge(attributes))
  end

  def signed_oidc_claims(setting, nonce:, **overrides)
    { "iss" => setting.issuer, "sub" => "employee-1", "aud" => setting.client_id,
      "iat" => Time.current.to_i, "exp" => 5.minutes.from_now.to_i, "nonce" => nonce,
      "email" => "employee@#{setting.tenant.slug}.test", "email_verified" => true,
      "name" => "Verified Employee", "groups" => [ "store-team" ] }.merge(overrides.stringify_keys)
  end

  def oidc_token(claims, key: KEY, algorithm: "RS256", headers: {})
    JWT.encode(claims, key, algorithm, { kid: JWK.kid }.merge(headers))
  end

  def start_oidc(setting)
    Oidc::SafeHttp.stub(:address_for, "93.184.216.34") do
      get oidc_login_path(setting.tenant.slug)
    end
    assert_response :redirect
    URI.decode_www_form(URI.parse(response.location).query).to_h
  end

  def complete_oidc(setting, flow, claims: {}, token: nil, code: "provider-code", jwks: nil)
    payload = signed_oidc_claims(setting, nonce: flow.fetch("nonce"), **claims.symbolize_keys)
    http = lambda do |url, **options|
      case url
      when setting.token_endpoint
        assert_equal [ setting.client_id, setting.client_secret ], options[:credentials]
        assert_equal code, options[:form][:code]
        assert_equal "authorization_code", options[:form][:grant_type]
        verifier = options[:form][:code_verifier]
        assert_equal flow["code_challenge"], Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
        assert_equal flow["redirect_uri"], options[:form][:redirect_uri]
        { "id_token" => token || oidc_token(payload) }
      when setting.jwks_uri
        jwks || JSON.parse(JSON.generate({ keys: [ JWK.export ] }))
      else
        raise "Unexpected provider endpoint"
      end
    end
    Oidc::SafeHttp.stub(:json, http) do
      get oidc_callback_path(setting.tenant.slug), params: { state: flow.fetch("state"), code: code }
    end
  end
end
