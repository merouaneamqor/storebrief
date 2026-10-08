module Vazivo
  # Recurring task briefs. The brief HQ sends is the series source: it carries
  # the rule and the next due date. Each occurrence is a plain sent Communication
  # (with Deliveries) cloned from it, so stores, radar, proof and escalation work
  # unchanged. A store that still has the previous occurrence open keeps that one
  # as its current instance instead of receiving a duplicate.
  class Recurrence
    FREQUENCIES = %w[daily weekly custom].freeze
    MAX_INTERVAL = 365
    MAX_CATCH_UP = 1000

    class << self
      # Builds a clean rule hash from form input. Blank or unknown frequency means no recurrence.
      def normalize(attrs)
        attrs = attrs.to_unsafe_h if attrs.respond_to?(:to_unsafe_h)
        attrs = (attrs || {}).to_h.stringify_keys
        frequency = attrs["frequency"].to_s
        return {} unless FREQUENCIES.include?(frequency)

        rule = { "frequency" => frequency }
        case frequency
        when "weekly"
          days = Array(attrs["weekdays"]).map(&:to_s).reject(&:blank?).map(&:to_i).select { |d| d.between?(0, 6) }.uniq.sort
          rule["weekdays"] = days
        when "custom"
          rule["interval"] = attrs["interval"].to_i
        end
        ends_on = parse_date(attrs["ends_on"])
        rule["ends_on"] = ends_on.iso8601 if ends_on
        rule
      end

      def errors_for(rule)
        return [] if rule.blank?

        errors = []
        errors << :frequency unless FREQUENCIES.include?(rule["frequency"])
        errors << :weekdays if rule["frequency"] == "weekly" && Array(rule["weekdays"]).empty?
        errors << :interval if rule["frequency"] == "custom" && !rule["interval"].to_i.between?(1, MAX_INTERVAL)
        errors << :ends_on if rule["ends_on"].present? && parse_date(rule["ends_on"]).nil?
        errors
      end

      # First scheduled date strictly after +date+, or nil once the series has ended.
      def next_on(rule, date)
        return if rule.blank? || errors_for(rule).any?

        candidate = case rule["frequency"]
        when "daily" then date + 1
        when "custom" then date + rule["interval"].to_i
        when "weekly"
          days = Array(rule["weekdays"]).map(&:to_i)
          (1..7).map { |offset| date + offset }.find { |day| days.include?(day.wday) }
        end
        ends_on = parse_date(rule["ends_on"])
        return if candidate.nil? || (ends_on && candidate > ends_on)

        candidate
      end

      # Called when a recurring brief is sent: arms the scheduler for the next date.
      def arm!(communication, from: Schedule.now.to_date)
        return unless communication.recurring?

        communication.update_column(:recurrence_next_on, next_on(communication.recurrence_rule, from))
      end

      def stop!(communication)
        communication.update_column(:recurrence_next_on, nil)
      end

      def spawn_all!(today: Schedule.now.to_date)
        Communication.recurrence_due(today).find_each.filter_map { |source| spawn!(source, today:) }
      end

      # Creates the occurrence due on or before +today+. Returns it, or nil when
      # nothing was created (not due yet, or every store still has work in flight).
      def spawn!(source, today: Schedule.now.to_date)
        source.with_lock do
          next unless source.recurring? && source.sent? && source.recurrence_next_on && source.recurrence_next_on <= today

          date = latest_due_date(source.recurrence_rule, source.recurrence_next_on, today)
          upcoming = next_on(source.recurrence_rule, date)
          occurrence = build_occurrence!(source, date)
          source.update_column(:recurrence_next_on, upcoming)
          occurrence
        end
      end

      # Stores of the series that already hold an unfinished instance.
      def in_flight_store_ids(source)
        Delivery.joins(:communication)
                .where(communications: { tenant_id: source.tenant_id, status: "sent" })
                .where(status: "pending")
                .merge(Communication.in_series(source.id))
                .distinct
                .pluck(:org_unit_id)
      end

      private

      # A job that was down for days only creates the newest missed occurrence.
      def latest_due_date(rule, from, today)
        date = from
        MAX_CATCH_UP.times do
          following = next_on(rule, date)
          break if following.nil? || following > today

          date = following
        end
        date
      end

      def build_occurrence!(source, date)
        store_ids = source.deliveries.pluck(:org_unit_id) - in_flight_store_ids(source)
        return if store_ids.empty?

        occurrence = nil
        source.tenant.transaction do
          occurrence = source.tenant.communications.create!(
            author: source.author,
            playbook: source.playbook,
            recurrence_parent: source,
            occurrence_on: date,
            format: source.format,
            status: "draft",
            source: source.source,
            title_fr: source.title_fr,
            title_ar: source.title_ar,
            body_fr: source.body_fr,
            body_ar: source.body_ar,
            requires_proof: source.requires_proof,
            priority: source.priority,
            due_at: due_at_for(source, date)
          )
          copy_questions(source, occurrence)
          occurrence.send_to!(store_ids)
        end
        occurrence
      end

      def copy_questions(source, occurrence)
        source.communication_questions.each do |question|
          occurrence.communication_questions.create!(
            question.attributes.slice("position", "question_type", "title_fr", "title_ar", "required", "options")
          )
        end
      end

      # Same clock time as the source deadline, on the occurrence date.
      def due_at_for(source, date)
        clock = source.due_at&.in_time_zone(Schedule::ZONE)
        return Schedule.default_due(source.tenant, nil).change(year: date.year, month: date.month, day: date.day) if clock.nil?

        Schedule::ZONE.local(date.year, date.month, date.day, clock.hour, clock.min)
      end

      def parse_date(value)
        return value if value.is_a?(Date)

        Date.iso8601(value.to_s) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
