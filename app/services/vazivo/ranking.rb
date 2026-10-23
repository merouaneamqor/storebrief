module Vazivo
  # Weekly store ranking from real execution: completion, on-time work,
  # coaching verdicts, and improvement versus the previous week.
  class Ranking
    Row = Struct.new(
      :store, :percent, :done, :total, :on_time_percent, :conforme, :previous_percent, :delta,
      keyword_init: true
    )
    Result = Struct.new(:rows, :podium, :awards, :week_start, :vm_rows, :vm_areas, keyword_init: true)

    def self.for(tenant, on: Schedule.now, date_range: nil, store_ids: nil)
      new(tenant, on, date_range: date_range, store_ids: store_ids).call
    end

    def initialize(tenant, on, date_range: nil, store_ids: nil)
      @tenant = tenant
      @date_range = date_range
      @store_ids = store_ids
      @on = on.in_time_zone(Schedule::ZONE)
    end

    def call
      week_start = @on.beginning_of_week
      range = @date_range&.times || (week_start...(week_start + 1.week))
      previous_range = if @date_range
        days = (@date_range.to - @date_range.from).to_i + 1
        (@date_range.from - days).in_time_zone(Schedule::ZONE)...@date_range.from.in_time_zone(Schedule::ZONE)
      else
        (week_start - 1.week)...week_start
      end
      current = scores(range)
      previous = scores(previous_range)
      rows = @tenant.org_units.stores.order(:name).filter_map do |store|
        next if @store_ids && !@store_ids.include?(store.id)

        now_score = current.fetch(store.id, nil)
        next if now_score.nil?

        prev = previous.fetch(store.id, nil)
        prev_percent = prev&.dig(:percent)
        percent = now_score[:percent]
        Row.new(
          store: store,
          percent: percent,
          done: now_score[:done],
          total: now_score[:total],
          on_time_percent: now_score[:on_time_percent],
          conforme: now_score[:conforme],
          previous_percent: prev_percent,
          delta: prev_percent.nil? || percent.nil? ? nil : percent - prev_percent
        )
      end
      active = rows.select { |row| row.total.positive? }
      vm = VmScore.new(@tenant, @date_range&.dates || (week_start.to_date..(week_start + 6.days).to_date), store_ids: @store_ids)
      vm_rows = vm.call.values.sort_by { |score| [ -score.percent, score.store.name ] }
      Result.new(
        rows: active.sort_by { |row| [ -row.percent.to_i, row.store.name ] },
        podium: active.sort_by { |row| [ -row.percent.to_i, row.store.name ] }.first(3),
        awards: awards_for(active).merge(merchandising: vm_rows.first),
        week_start: range.begin.to_date,
        vm_rows: vm_rows,
        vm_areas: vm.areas
      )
    end

    private

    def awards_for(active)
      {
        execution: active.max_by { |row| [ row.percent.to_i, row.done ] },
        vm: active.select { |row| row.conforme.positive? }.max_by(&:conforme),
        improvement: active.select { |row| row.delta&.positive? }.max_by(&:delta),
        team: active.select { |row| row.done.positive? }.max_by { |row| row.on_time_percent.to_i }
      }
    end

    def scores(range)
      grouped = Hash.new { |hash, key| hash[key] = { done: 0, total: 0, on_time: 0, conforme: 0 } }
      deliveries(range).each do |delivery|
        bucket = grouped[delivery.org_unit_id]
        bucket[:total] += 1
        next unless delivery.finished?

        bucket[:done] += 1
        bucket[:on_time] += 1 if delivery.due_at.blank? || (delivery.completed_at && delivery.completed_at <= delivery.due_at)
        bucket[:conforme] += 1 if delivery.verdict == "conforme"
      end
      checks(range).each do |delivery|
        bucket = grouped[delivery.org_unit_id]
        bucket[:total] += 1
        next unless delivery.finished?

        bucket[:done] += 1
        bucket[:on_time] += 1 if delivery.due_at.blank? || (delivery.completed_at && delivery.completed_at <= delivery.due_at)
      end
      grouped.transform_values do |bucket|
        bucket.merge(
          percent: bucket[:total].zero? ? nil : ((bucket[:done].to_f / bucket[:total]) * 100).round,
          on_time_percent: bucket[:done].zero? ? 0 : ((bucket[:on_time].to_f / bucket[:done]) * 100).round
        )
      end
    end

    def deliveries(range)
      Delivery.joins(:communication)
              .where(communications: { tenant_id: @tenant.id, status: "sent" })
              .where(created_at: range)
    end

    def checks(range)
      ChecklistDelivery.joins(:checklist)
                       .where(checklists: { tenant_id: @tenant.id, status: "sent" })
                       .where(created_at: range)
    end
  end
end
