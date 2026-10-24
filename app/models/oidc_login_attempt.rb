class OidcLoginAttempt < ApplicationRecord
  belongs_to :tenant

  def self.digest(value)
    Digest::SHA256.hexdigest(value.to_s)
  end

  def consume!(browser:, issuer:, client_id:)
    with_lock do
      valid = consumed_at.nil? && expires_at.future? && self.issuer == issuer && self.client_id == client_id &&
        ActiveSupport::SecurityUtils.secure_compare(browser_digest, self.class.digest(browser))
      raise Oidc::Error unless valid

      update!(consumed_at: Time.current)
    end
  end

  def code_verifier
    Oidc::Secrets.decrypt(code_verifier_ciphertext, purpose: "oidc pkce")
  end
end
