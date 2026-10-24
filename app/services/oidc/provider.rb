require "jwt"

module Oidc
  class Provider
    def initialize(setting)
      @setting = setting
    end

    def authorization_url(attempt:, state:, nonce:, challenge:)
      uri = SafeHttp.uri(@setting.authorization_endpoint)
      SafeHttp.address_for(uri)
      params = URI.decode_www_form(uri.query.to_s).to_h.merge(
        "client_id" => @setting.client_id, "redirect_uri" => attempt.redirect_uri,
        "response_type" => "code", "scope" => "openid email profile",
        "state" => state, "nonce" => nonce, "code_challenge" => challenge,
        "code_challenge_method" => "S256"
      )
      uri.query = URI.encode_www_form(params)
      uri.to_s
    end

    def claims(code:, attempt:)
      response = SafeHttp.json(@setting.token_endpoint,
        form: { grant_type: "authorization_code", code: code, redirect_uri: attempt.redirect_uri, code_verifier: attempt.code_verifier },
        credentials: [ @setting.client_id, @setting.client_secret ])
      raise Error unless response.is_a?(Hash) && response["id_token"].is_a?(String) && response["id_token"].bytesize < 32.kilobytes

      verify(response["id_token"], attempt: attempt)
    end

    def verify(token, attempt:)
      _, header = JWT.decode(token, nil, false)
      raise Error unless header["alg"] == "RS256" && header["kid"].is_a?(String) && header["kid"].present? && header["kid"].size <= 128
      raise Error if %w[jku jwk x5u].any? { |field| header.key?(field) }

      jwks = SafeHttp.json(@setting.jwks_uri)
      keys = jwks.is_a?(Hash) ? jwks["keys"] : nil
      raise Error unless keys.is_a?(Array) && keys.size <= 100

      keys = keys.select { |key| key.is_a?(Hash) && key["kid"] == header["kid"] && key["kty"] == "RSA" && [ nil, "sig" ].include?(key["use"]) && [ nil, "RS256" ].include?(key["alg"]) }
      raise Error unless keys.one?

      jwk = keys.first
      valid_key = jwk["n"].is_a?(String) && jwk["n"].match?(/\A[A-Za-z0-9_-]{1,2048}\z/) &&
        jwk["e"].is_a?(String) && jwk["e"].match?(/\A[A-Za-z0-9_-]{1,12}\z/)
      raise Error unless valid_key

      key = JWT::JWK.import(keys.first).public_key
      raise Error unless key.n.num_bits.between?(2048, 8192)

      payload, = JWT.decode(token, key, true, algorithms: [ "RS256" ],
        iss: @setting.issuer, verify_iss: true, aud: @setting.client_id, verify_aud: true,
        verify_expiration: true, verify_not_before: true, verify_iat: true,
        required_claims: %w[iss sub aud exp iat nonce email email_verified])
      valid = payload["sub"].is_a?(String) && payload["sub"].present? && payload["sub"].size <= 255 &&
        payload["exp"].is_a?(Numeric) && payload["iat"].is_a?(Numeric) && payload["iat"] <= Time.current.to_i + 30 &&
        payload["email_verified"] == true && payload["email"].is_a?(String) && payload["email"].match?(URI::MailTo::EMAIL_REGEXP) &&
        payload["nonce"].is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(OidcLoginAttempt.digest(payload["nonce"]), attempt.nonce_digest)
      raise Error unless valid
      raise Error if (payload["aud"].is_a?(Array) && payload["aud"].size > 1 && payload["azp"] != @setting.client_id) || (payload.key?("azp") && payload["azp"] != @setting.client_id)

      payload
    rescue JWT::DecodeError, JWT::JWKError, OpenSSL::OpenSSLError, ArgumentError, TypeError
      raise Error
    end
  end
end
