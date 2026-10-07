module Vazivo
  # HQ view of weekly task completion and overdue work, rolled up by region.
  class TaskMonitoring
    RegionRow = Struct.new(:id, :name, :done, :total, :percent, :overdue, keyword_init: true)
    Snapshot = Struct.new(:percent, :done, :total, :overdue, :regions, keyword_init: true)

    def self.for(tenant)
      new(tenant).snapshot
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def snapshot
      ranking = Ranking.for(@tenant)
      rows = ranking.rows
      done = rows.sum(&:done)
      total = rows.sum(&:total)
      percent = total.zero? ? nil : ((done.to_f / total) * 100).round
      overdue = network_overdue_count
      regions = @tenant.org_units.regions.order(:name).map { |region| region_row(region, ranking.rows) }

      Snapshot.new(percent: percent, done: done, total: total, overdue: overdue, regions: regions)
    end

    def store_rows_for(region)
      ranking = Ranking.for(@tenant)
      store_ids = region.descendant_stores.pluck(:id)
      ranking.rows.select { |row| store_ids.include?(row.store.id) }
    end

    private

    def region_row(region, rows)
      store_ids = region.descendant_stores.pluck(:id)
      scoped = rows.select { |row| store_ids.include?(row.store.id) }
      done = scoped.sum(&:done)
      total = scoped.sum(&:total)
      percent = total.zero? ? nil : ((done.to_f / total) * 100).round
      RegionRow.new(
        id: region.id,
        name: region.name,
        done: done,
        total: total,
        percent: percent,
        overdue: overdue_for(store_ids)
      )
    end

    def network_overdue_count
      overdue_for(@tenant.org_units.stores.pluck(:id))
    end

    def overdue_for(store_ids)
      return 0 if store_ids.empty?

      briefs = Delivery.joins(:communication)
                       .where(org_unit_id: store_ids, communications: { tenant_id: @tenant.id, status: "sent" })
                       .where.not(status: %w[completed read])
                       .where.not(due_at: nil)
                       .where("deliveries.due_at < ?", Time.current)
                       .count
      checks = ChecklistDelivery.joins(:checklist)
                                .where(org_unit_id: store_ids, checklists: { tenant_id: @tenant.id, status: "sent" })
                                .where.not(status: "completed")
                                .where.not(due_at: nil)
                                .where("checklist_deliveries.due_at < ?", Time.current)
                                .count
      briefs + checks
    end
  end
end
