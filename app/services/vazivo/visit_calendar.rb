module Vazivo
  # Month or week grid (Monday first) over a scoped set of visits.
  class VisitCalendar
    VIEWS = %w[month week].freeze

    attr_reader :view, :anchor

    def initialize(visits:, view: "month", date: nil)
      @visits = visits
      @view = VIEWS.include?(view.to_s) ? view.to_s : "month"
      @anchor = parse_date(date)
    end

    def month?
      view == "month"
    end

    def days
      (first_day..last_day).to_a
    end

    def weeks
      days.each_slice(7).to_a
    end

    def visits_by_day
      @visits_by_day ||= visits.group_by { |visit| visit.planned_at.in_time_zone(Schedule::ZONE).to_date }
    end

    def visits
      @visits_loaded ||= @visits.where(planned_at: range_start...range_end).upcoming_first.to_a
    end

    def in_period?(day)
      !month? || day.month == anchor.month
    end

    def previous_date
      month? ? anchor.beginning_of_month.prev_month : anchor - 7.days
    end

    def next_date
      month? ? anchor.beginning_of_month.next_month : anchor + 7.days
    end

    def today
      Schedule.now.to_date
    end

    private

    def first_day
      month? ? anchor.beginning_of_month.beginning_of_week(:monday) : anchor.beginning_of_week(:monday)
    end

    def last_day
      month? ? anchor.end_of_month.end_of_week(:monday) : anchor.end_of_week(:monday)
    end

    def range_start
      Schedule::ZONE.local(first_day.year, first_day.month, first_day.day)
    end

    def range_end
      Schedule::ZONE.local(last_day.year, last_day.month, last_day.day) + 1.day
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      today
    end
  end
end
