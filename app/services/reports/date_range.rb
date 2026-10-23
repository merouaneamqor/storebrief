module Reports
  # Inclusive calendar dates in the retailer's operating timezone.
  class DateRange
    EARLIEST_DATE = Date.new(2000, 1, 1)
    LATEST_DATE = Date.new(2100, 12, 31)
    MAX_YEARS = 5

    attr_reader :from, :to

    def initialize(from: nil, to: nil, default_from: Vazivo::Schedule.now.to_date - 11.weeks, default_to: Vazivo::Schedule.now.to_date)
      @from = (parse(from) || default_from).clamp(EARLIEST_DATE, LATEST_DATE)
      @to = (parse(to) || default_to).clamp(EARLIEST_DATE, LATEST_DATE)
      @from, @to = @to, @from if @from > @to
      # Keep the latest five calendar years and expose these normalized dates
      # to the filter UI. Bound before timezone conversion or bucket iteration.
      @from = [ @from, @to - MAX_YEARS.years + 1.day ].max
    end

    def dates
      from..to
    end

    def times
      from.in_time_zone(Vazivo::Schedule::ZONE)...(to + 1.day).in_time_zone(Vazivo::Schedule::ZONE)
    end

    private

    def parse(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end
  end
end
