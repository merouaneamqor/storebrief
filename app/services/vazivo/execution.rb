module Vazivo
  # Shared lateness rules for a brief delivery and a checklist delivery.
  # Without a deadline there is nothing to chase.
  module Execution
    def finished?
      %w[completed read].include?(status)
    end

    def late?
      return false if finished? || due_at.blank?

      due_at < Time.current
    end

    def urgent?
      return false if finished? || late? || due_at.blank?

      due_at <= 3.hours.from_now
    end

    def due_today?
      return false if finished? || due_at.blank?

      due_at.in_time_zone(Schedule::ZONE).to_date == Schedule.now.to_date
    end

    def now?
      late? || urgent? || due_today?
    end

    def tone
      return "done" if finished?
      return "late" if late?
      return "urgent" if urgent?

      "open"
    end
  end
end
