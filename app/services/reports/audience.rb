module Reports
  class Audience
    def self.eligible?(user)
      (user.hq? || user.area?) && user.allows?(:reports)
    end

    def self.enabled?(user)
      tenant = user.tenant
      eligible?(user) && %i[morocco_ops reports email_alerts].all? { |flag| tenant.feature?(flag) }
    end
  end
end
