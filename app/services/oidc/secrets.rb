module Oidc
  # Uses the existing application secret, with a separate authenticated purpose.
  # Rotating SECRET_KEY_BASE requires re-entering OIDC client secrets.
  module Secrets
    module_function

    def encrypt(value, purpose:)
      encryptor.encrypt_and_sign(value, purpose: purpose)
    end

    def decrypt(value, purpose:)
      encryptor.decrypt_and_verify(value, purpose: purpose) || raise(Error)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      raise Error
    end

    def encryptor
      key = Rails.application.key_generator.generate_key("oidc credentials", 32)
      ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
    end
  end
end
