module Reports
  # Inclusive calendar dates in the retailer's operating timezone.
  class DateRange
    attr_reader :from, :to

    def initialize(from: nil, to: nil, default_from: Vazivo::Schedule.now.to_date - 11.weeks, default_to: Vazivo::Schedule.now.to_date)
      @from = parse(from) || default_from
      @to = parse(to) || default_to
      @from, @to = @to, @from if @from > @to
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
