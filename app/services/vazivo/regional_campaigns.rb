module Vazivo
  # Area/region rollup of live playbook campaign execution: compliance % per
  # region with store drill-down, in the same shape as HqBoard region groups.
  class RegionalCampaigns
    StoreRow = Struct.new(
      :store_name, :owner_name, :due_at, :tone, :finished, :overdue,
      :campaign_title, :steps_done, :steps_total, :path,
      keyword_init: true
    )
    Region = Struct.new(
      :id, :label, :total, :done, :overdue, :percent, :stores,
      keyword_init: true
    )
    Snapshot = Struct.new(:regions, :total, :done, :overdue, :percent, keyword_init: true) do
      def any?
        total.positive?
      end
    end

    def self.for(tenant)
      new(tenant).snapshot
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def snapshot
      deliveries = live_deliveries
      return empty_snapshot if deliveries.empty?

      regions = groups_by_region(deliveries)
      done = deliveries.count(&:completed?)
      overdue = deliveries.count(&:late?)
      Snapshot.new(
        regions: regions,
        total: deliveries.size,
        done: done,
        overdue: overdue,
        percent: percent_of(done, deliveries.size)
      )
    end

    private

    def routes
      Rails.application.routes.url_helpers
    end

    def empty_snapshot
      Snapshot.new(regions: [], total: 0, done: 0, overdue: 0, percent: 0)
    end

    # Same live set as CampaignDashboard: sent playbook checklists that still
    # have at least one pending store.
    def live_checklists
      @tenant.checklists.sent
             .where.not(playbook_id: nil)
             .where(id: ChecklistDelivery.pending.select(:checklist_id))
             .includes(:playbook, :checklist_items, checklist_deliveries: [ :org_unit, :assignee, :checklist_item_responses ])
             .order(Arel.sql("checklists.campaign_on ASC NULLS LAST"), :id)
    end

    def live_deliveries
      live_checklists.flat_map(&:checklist_deliveries)
    end

    def groups_by_region(deliveries)
      units = org_units_by_id
      deliveries.group_by { |delivery| region_name_for(delivery.org_unit, units) }.map do |name, rows|
        done = rows.count(&:completed?)
        overdue = rows.count(&:late?)
        Region.new(
          id: "region-#{name.parameterize}",
          label: name,
          total: rows.size,
          done: done,
          overdue: overdue,
          percent: percent_of(done, rows.size),
          stores: store_rows(rows)
        )
      end.sort_by { |region| [ -region.overdue, region.percent, region.label ] }
    end

    def store_rows(rows)
      rows.sort_by { |row| [ row.completed? ? 1 : 0, row.late? ? 0 : 1, row.org_unit.name ] }.map do |delivery|
        checklist = delivery.checklist
        StoreRow.new(
          store_name: delivery.org_unit.name,
          owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
          due_at: delivery.due_at,
          tone: delivery.tone,
          finished: delivery.completed?,
          overdue: delivery.late?,
          campaign_title: checklist.playbook&.title || checklist.title,
          steps_done: delivery.checklist_item_responses.count(&:completed?),
          steps_total: checklist.checklist_items.size,
          path: routes.checklist_path(checklist, anchor: "store-#{delivery.org_unit_id}")
        )
      end
    end

    def org_units_by_id
      @org_units_by_id ||= @tenant.org_units.index_by(&:id)
    end

    def region_name_for(store, units)
      current = units[store.parent_id]
      guard = 0
      while current && guard < 8
        return current.name if current.unit_type == "region"

        current = units[current.parent_id]
        guard += 1
      end
      I18n.t("morocco.hq.monitoring.unassigned_region")
    end

    def percent_of(done, total)
      return 0 if total.zero?

      ((done.to_f / total) * 100).round
    end
  end
end
