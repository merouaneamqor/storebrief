class TenantOidcSetting < ApplicationRecord
  belongs_to :tenant
  URL_FIELDS = %i[issuer authorization_endpoint token_endpoint jwks_uri].freeze

  validates(*URL_FIELDS, length: { maximum: 255 }, allow_blank: true)
  validates :client_id, length: { maximum: 255 }
  validates :client_id, presence: true, if: :enabled?
  validates :client_secret_ciphertext, presence: true, if: :enabled?
  validate :provider_urls
  validate :mapping_shape

  def client_secret=(value)
    self.client_secret_ciphertext = Oidc::Secrets.encrypt(value, purpose: "oidc client secret") if value.present?
  end

  def client_secret
    Oidc::Secrets.decrypt(client_secret_ciphertext, purpose: "oidc client secret")
  end

  def ready?
    enabled? && client_id.present? && client_secret_ciphertext.present? && URL_FIELDS.all? { |field| self[field].present? }
  end

  def role_mappings_json
    @role_mappings_json || JSON.pretty_generate(role_mappings)
  end

  def role_mappings_json=(value)
    @role_mappings_json = value
    self.role_mappings = JSON.parse(value.presence || "[]")
    @invalid_json = false
  rescue JSON::ParserError
    @invalid_json = true
  end

  private

  def provider_urls
    URL_FIELDS.each do |field|
      value = self[field]
      if value.blank?
        errors.add(field, :blank) if enabled?
      else
        begin
          Oidc::SafeHttp.uri(value)
        rescue Oidc::Error
          errors.add(field, :invalid)
        end
      end
    end
    errors.add(:issuer, :invalid) if issuer.present? && URI.parse(issuer).query.present?
  rescue URI::InvalidURIError
    errors.add(:issuer, :invalid)
  end

  def mapping_shape
    unless !@invalid_json && role_mappings.is_a?(Array) && role_mappings.size <= 100
      errors.add(:role_mappings, :invalid)
      return
    end
    role_mappings.each do |mapping|
      unless mapping.is_a?(Hash) && mapping["claim"].to_s.match?(/\A[a-zA-Z][a-zA-Z0-9_]{0,63}\z/) && mapping["value"].is_a?(String) && mapping["value"].present? && mapping["value"].size <= 255
        errors.add(:role_mappings, :invalid)
        next
      end
      keys_valid = (mapping.keys - %w[claim value role org_unit_id tenant_role_id]).empty?
      ids_valid = mapping["org_unit_id"].to_s.match?(/\A[1-9]\d{0,17}\z/) &&
        (mapping["tenant_role_id"].blank? || mapping["tenant_role_id"].to_s.match?(/\A[1-9]\d{0,17}\z/))
      unless keys_valid && ids_valid
        errors.add(:role_mappings, :invalid)
        next
      end
      unit = tenant.org_units.find_by(id: mapping["org_unit_id"])
      role = tenant.tenant_roles.find_by(id: mapping["tenant_role_id"]) if mapping["tenant_role_id"].present?
      base = role&.base_role || mapping["role"]
      valid = unit && Membership::ROLES.include?(base) && (base != "hq" || role) && (!mapping["tenant_role_id"].present? || role)
      errors.add(:role_mappings, :invalid) unless valid
    end
  end
end
