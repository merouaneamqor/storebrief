module Reports
  # Completion of work assigned in each period, using its current status.
  # Missing observations stay nil rather than appearing as 0% compliance.
  class ComplianceTrends
    attr_reader :interval, :group_by

    def initialize(tenant, date_range:, store_ids: nil, interval: nil, group_by: nil)
      @tenant = tenant
      @date_range = date_range
      @store_ids = store_ids
      @interval = %w[week month].include?(interval) ? interval : "week"
      @group_by = %w[region area store].include?(group_by) ? group_by : "region"
    end

    def chart
      units = @tenant.org_units.index_by(&:id)
      stores = units.values.select { |unit| unit.store? && (@store_ids.nil? || @store_ids.include?(unit.id)) }
      groups = stores.group_by { |store| ancestor(store, units) }
      observations = deliveries(stores.map(&:id))
      buckets = periods
      {
        labels: buckets.map(&:iso8601),
        series: groups.map do |unit, members|
          ids = members.map(&:id)
          rows = observations.select { |row| ids.include?(row[0]) }.group_by { |row| period(row[1].in_time_zone(Vazivo::Schedule::ZONE).to_date) }
          { name: unit&.name || I18n.t("reports.unassigned"), values: buckets.map do |date|
            work = rows.fetch(date, [])
            work.empty? ? nil : (100.0 * work.count { |row| %w[read completed].include?(row[2]) } / work.size).round
          end }
        end
      }
    end

    private

    def ancestor(store, units)
      current = store
      visited = []
      while current && !visited.include?(current.id)
        return current if current.unit_type == group_by

        visited << current.id
        current = units[current.parent_id]
      end
    end

    def period(date)
      interval == "month" ? date.beginning_of_month : date.beginning_of_week
    end

    def periods
      result = []
      date = period(@date_range.from)
      while date <= @date_range.to
        result << date
        date = interval == "month" ? date.next_month : date + 1.week
      end
      result
    end

    def deliveries(ids)
      briefs = Delivery.joins(:communication).where(communications: { tenant_id: @tenant.id, status: "sent" })
      checks = ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: @tenant.id, status: "sent" })
      [ briefs, checks ].flat_map do |scope|
        scope.where(org_unit_id: ids, created_at: @date_range.times).pluck(:org_unit_id, :created_at, :status)
      end
    end
  end
end
