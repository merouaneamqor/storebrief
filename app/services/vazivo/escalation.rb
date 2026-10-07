module Vazivo
  # Once a task is past its deadline, chase it up the Moroccan store line:
  # 24h store manager, 48h area manager, 72h head office.
  # Items without a deadline are left alone.
  class Escalation
    LEVELS = {
      1 => "store_manager",
      2 => "area_manager",
      3 => "hq"
    }.freeze

    def self.sweep_all!(now: Time.current)
      Tenant.find_each { |tenant| sweep!(tenant, now:) }
    end

    def self.sweep!(tenant, now: Time.current)
      Delivery.joins(:communication)
              .includes(:communication)
              .where(communications: { tenant_id: tenant.id, status: "sent" })
              .where.not(status: %w[completed read])
              .where.not(due_at: nil)
              .find_each { |delivery| call(delivery, now:) }

      ChecklistDelivery.joins(:checklist)
                       .includes(:checklist)
                       .where(checklists: { tenant_id: tenant.id, status: "sent" })
                       .where.not(status: "completed")
                       .where.not(due_at: nil)
                       .find_each { |delivery| call(delivery, now:) }
    end

    def self.call(record, now: Time.current)
      return if record.finished?
      return if record.due_at.blank?
      return if record.due_at > now

      hours = ((now - record.due_at) / 1.hour).floor
      level = case hours
      when 72.. then 3
      when 48...72 then 2
      when 24...48 then 1
      else 0
      end
      return if level <= record.escalation_level.to_i

      tenant = tenant_for(record)
      ((record.escalation_level.to_i + 1)..level).each do |step|
        record.escalation_events.create!(
          tenant: tenant,
          level: step,
          notified_role: LEVELS.fetch(step)
        )
      end
      record.update!(escalation_level: level, escalated_at: now)
    end

    def self.tenant_for(record)
      case record
      when Delivery then record.communication.tenant
      when ChecklistDelivery then record.checklist.tenant
      else
        raise ArgumentError, "unsupported record"
      end
    end
  end
end
