module Reports
  class Digest
    attr_reader :date_range, :snapshot, :ranking

    def initialize(user, date_range:, now: Time.current)
      @date_range = date_range
      @tenant = user.tenant
      @store_ids = user.permitted_store_ids(:reports)
      @snapshot = Reports::Snapshot.new(@tenant, date_range: date_range, store_ids: @store_ids)
      @ranking = Vazivo::Ranking.for(@tenant, date_range: date_range, store_ids: @store_ids)
      @now = now
    end

    def compliance
      total = ranking.rows.sum(&:total)
      total.zero? ? 0 : (100.0 * ranking.rows.sum(&:done) / total).round
    end

    def overdue
      briefs = Delivery.joins(:communication).where(communications: { tenant_id: @tenant.id, status: "sent" })
      checks = ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: @tenant.id, status: "sent" })
      [ briefs, checks ].sum do |scope|
        scope.where(org_unit_id: @store_ids, created_at: date_range.times, status: "pending").where(scope.klass.arel_table[:due_at].lt(@now)).count
      end
    end

    def top_stores
      ranking.rows.first(3)
    end

    def bottom_stores
      ranking.rows.last(3).reverse
    end
  end
end
