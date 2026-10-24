module Vazivo
  # One grid for real, assigned work. Recurring tasks use persisted occurrences,
  # never projections that a store has not actually received.
  class RetailCalendar < VisitCalendar
    TYPES = %w[visit task campaign].freeze
    Event = Struct.new(:kind, :record, :day, :at, :milestone, keyword_init: true) do
      def title
        case kind
        when "visit" then record.org_unit.name
        when "task" then record.communication.title
        when "campaign" then record.checklist.title
        end
      end

      def store_name = record.org_unit.name
      def status = record.status
    end

    def initialize(visits:, task_deliveries:, campaign_deliveries:, type: nil, **options)
      super(visits: visits, **options)
      @task_deliveries = task_deliveries
      @campaign_deliveries = campaign_deliveries
      @type = type.to_s.presence_in(TYPES)
    end

    def events
      @events ||= begin
        rows = []
        rows.concat(visit_events) if include_type?("visit")
        rows.concat(task_events) if include_type?("task")
        rows.concat(campaign_events) if include_type?("campaign")
        rows.sort_by { |event| [ event.day, event.at&.to_i || 0, event.kind, event.record.id ] }
      end
    end

    def events_by_day
      @events_by_day ||= events.group_by(&:day)
    end

    private

    def include_type?(kind)
      @type.nil? || @type == kind
    end

    def visit_events
      visits.map do |visit|
        at = visit.planned_at.in_time_zone(Schedule::ZONE)
        Event.new(kind: "visit", record: visit, day: at.to_date, at: at)
      end
    end

    def task_events
      @task_deliveries.where(due_at: range_start...range_end).map do |delivery|
        at = delivery.due_at.in_time_zone(Schedule::ZONE)
        Event.new(kind: "task", record: delivery, day: at.to_date, at: at)
      end
    end

    def campaign_events
      @campaign_deliveries.where(checklists: { starts_on: first_day..last_day })
                          .or(@campaign_deliveries.where(checklists: { campaign_on: first_day..last_day }))
                          .flat_map do |delivery|
        %w[starts_on campaign_on].filter_map do |milestone|
          day = delivery.checklist.public_send(milestone)
          next unless day && (first_day..last_day).cover?(day)

          Event.new(kind: "campaign", record: delivery, day: day, milestone: milestone)
        end
      end
    end
  end
end
