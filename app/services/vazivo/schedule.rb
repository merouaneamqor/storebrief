module Vazivo
  # Store clocks follow Africa/Casablanca. Ramadan mode moves anything
  # scheduled before opening to the hour the shop actually starts.
  class Schedule
    ZONE = ActiveSupport::TimeZone["Africa/Casablanca"]

    def self.zone
      ZONE
    end

    def self.now
      ZONE.now
    end

    def self.parse_local(value)
      return if value.blank?

      ZONE.parse(value.to_s)
    end

    def self.adjust(tenant, due_at)
      return if due_at.blank?

      local = due_at.in_time_zone(ZONE)
      open_hour, open_min = parse_hm(tenant.effective_open, fallback: [ 9, 0 ])
      return local if local.hour > open_hour || (local.hour == open_hour && local.min >= open_min)

      local.change(hour: open_hour, min: open_min, sec: 0)
    end

    def self.default_due(tenant, explicit = nil)
      return adjust(tenant, explicit) if explicit.present?

      now = ZONE.now
      close_hour, close_min = parse_hm(tenant.effective_close, fallback: [ 21, 0 ])
      due = now.change(hour: close_hour, min: close_min, sec: 0)
      due += 1.day if due <= now
      adjust(tenant, due)
    end

    def self.parse_hm(value, fallback:)
      return fallback if value.blank?

      hours, mins = value.to_s.split(":")
      [ hours.to_i, mins.to_i ]
    end
  end
end
