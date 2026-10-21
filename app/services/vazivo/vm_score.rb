module Vazivo
  # Scores merchandising missions per store. Rules:
  # - conforme 100, improve 60, non_conforme 0
  # - proof submitted after the deadline loses LATE_PENALTY points
  # - a target still not completed once the deadline has passed scores 0
  # Missions count in the week of their deadline, like the weekly ranking.
  class VmScore
    SCORES = { "conforme" => 100, "improve" => 60, "non_conforme" => 0 }.freeze
    LATE_PENALTY = 20

    StoreScore = Struct.new(:store, :percent, :scored, :conforme, keyword_init: true)
    AreaScore = Struct.new(:unit, :percent, :stores_count, :scored, keyword_init: true)

    def self.for(tenant, range)
      new(tenant, range).call
    end

    # Points for one target, or nil while it is still open and not yet due.
    def self.points(target, today: Date.current)
      mission = target.vm_mission
      if target.completed?
        base = SCORES.fetch(target.verdict, 0)
        late = target.submitted_at && target.submitted_at.to_date > mission.deadline_on
        late ? [ base - LATE_PENALTY, 0 ].max : base
      elsif mission.deadline_on < today
        0
      end
    end

    def initialize(tenant, range)
      @tenant = tenant
      @range = range
    end

    # { store_id => StoreScore } for stores with at least one scored target.
    def call
      @call ||= compute
    end

    # Average store score per parent unit (area or region), best first.
    def areas
      by_parent = call.values.group_by { |score| score.store.parent }
      by_parent.filter_map do |unit, scores|
        next if unit.nil?

        AreaScore.new(
          unit: unit,
          percent: (scores.sum(&:percent).to_f / scores.size).round,
          stores_count: scores.size,
          scored: scores.sum(&:scored)
        )
      end.sort_by { |area| [ -area.percent, area.unit.name ] }
    end

    private

    def compute
      buckets = Hash.new { |hash, key| hash[key] = { points: [], conforme: 0 } }
      targets.each do |target|
        value = self.class.points(target)
        next if value.nil?

        bucket = buckets[target.org_unit_id]
        bucket[:points] << value
        bucket[:conforme] += 1 if target.verdict == "conforme" && target.completed?
      end
      stores = @tenant.org_units.stores.where(id: buckets.keys).index_by(&:id)
      buckets.each_with_object({}) do |(id, bucket), result|
        store = stores[id]
        next if store.nil?

        result[id] = StoreScore.new(
          store: store,
          percent: (bucket[:points].sum.to_f / bucket[:points].size).round,
          scored: bucket[:points].size,
          conforme: bucket[:conforme]
        )
      end
    end

    def targets
      VmMissionTarget.joins(:vm_mission)
                     .includes(:vm_mission)
                     .where(vm_missions: { tenant_id: @tenant.id, deadline_on: @range })
    end
  end
end
