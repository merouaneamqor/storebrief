module Oidc
  class Provisioner
    def initialize(setting, claims)
      @setting = setting
      @tenant = setting.tenant
      @claims = claims
    end

    def call
      raise Error unless @tenant.oidc_sso_enabled? && @claims["iss"] == @setting.issuer && @claims["email_verified"] == true

      email = @claims.fetch("email").downcase.strip
      raise Error if User.super_admins.where("LOWER(email) = ?", email).exists?

      subject = @claims.fetch("sub")
      granted = false
      user = nil
      # Serializes identity linking and grant changes within this tenant.
      @tenant.with_lock do
        identity = @tenant.oidc_identities.find_by(issuer: @setting.issuer, subject: subject)
        matches = @tenant.users.where("LOWER(email) = ?", email)
        raise Error if !identity && matches.count > 1

        user = identity&.user || matches.first
        raise Error if user&.super_admin? || (user&.built_in_hq? && !identity&.admin_linked?)
        raise Error if user && (user.email.downcase != email || (user.oidc_identity && user.oidc_identity != identity))

        desired = mapped_grants
        raise Error if user.nil? && (!@setting.jit_enabled? || desired.blank?)

        user ||= @tenant.users.create!(name: @claims["name"].to_s.strip.presence&.first(120) || email.split("@").first,
          email: email, password: SecureRandom.urlsafe_base64(48), locale: "fr")
        identity ||= @tenant.oidc_identities.create!(user: user, issuer: @setting.issuer, subject: subject)
        # Only grants explicitly owned by this identity are revoked. Manual
        # memberships, including explicitly prelinked HQ admins, are untouched.
        identity.memberships.destroy_all
        Array(desired).each do |attributes|
          existing = user.memberships.find_by(org_unit_id: attributes[:org_unit_id])
          if existing
            granted ||= existing.role == attributes[:role] && existing.tenant_role_id == attributes[:tenant_role_id]
            next
          end
          user.memberships.create!(**attributes, oidc_identity: identity)
          granted = true
        end
        granted ||= identity.admin_linked? && user.built_in_hq?
      end
      # Revocations commit even when the provider no longer maps this account.
      raise Error unless granted

      user
    rescue KeyError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      raise Error
    end

    private

    def mapped_grants
      grants = Array(@setting.role_mappings).filter_map do |mapping|
        value = @claims[mapping["claim"]]
        matches = value.is_a?(String) ? value == mapping["value"] : (value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) } && value.include?(mapping["value"]))
        next unless matches

        unit = @tenant.org_units.find_by(id: mapping["org_unit_id"])
        role = @tenant.tenant_roles.find_by(id: mapping["tenant_role_id"]) if mapping["tenant_role_id"].present?
        base = role&.base_role || mapping["role"]
        raise Error unless unit && Membership::ROLES.include?(base) && (base != "hq" || role) && (!mapping["tenant_role_id"].present? || role)

        { org_unit_id: unit.id, role: base, tenant_role_id: role&.id }
      end.uniq
      return if grants.group_by { |grant| grant[:org_unit_id] }.any? { |_, entries| entries.size > 1 }

      grants
    end
  end
end
