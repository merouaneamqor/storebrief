module Vazivo
  class Assignment
    def self.stamp!(record, due_at:)
      store = record.org_unit
      manager = store.memberships.find_by(role: "store")&.user
      attrs = {}
      attrs[:assignee] = manager if record.assignee_id.blank? && manager
      attrs[:due_at] = due_at if record.due_at.blank? && due_at.present?
      record.update!(attrs) if attrs.any?
      record
    end

    # Open deliveries that were sent before owner/deadline stamping still need
    # a store manager and an end-of-day clock so the today board can work.
    def self.backfill!(tenant)
      due = Schedule.default_due(tenant, nil)

      Delivery.joins(:communication)
              .includes(:org_unit, org_unit: :memberships)
              .where(communications: { tenant_id: tenant.id, status: "sent" })
              .where.not(status: %w[completed read])
              .find_each { |delivery| stamp!(delivery, due_at: due) }

      ChecklistDelivery.joins(:checklist)
                       .includes(:org_unit, org_unit: :memberships)
                       .where(checklists: { tenant_id: tenant.id, status: "sent" })
                       .where.not(status: "completed")
                       .find_each { |delivery| stamp!(delivery, due_at: due) }

      reset_false_chases!(tenant)
    end

    # Clears chase markers that were set when age without a deadline counted as late.
    def self.reset_false_chases!(tenant)
      Delivery.joins(:communication)
              .where(communications: { tenant_id: tenant.id, status: "sent" })
              .where.not(status: %w[completed read])
              .where("escalation_level > 0")
              .find_each do |delivery|
        next if delivery.due_at.present? && delivery.due_at <= 24.hours.ago

        delivery.escalation_events.delete_all
        delivery.update!(escalation_level: 0, escalated_at: nil)
      end

      ChecklistDelivery.joins(:checklist)
                       .where(checklists: { tenant_id: tenant.id, status: "sent" })
                       .where.not(status: "completed")
                       .where("escalation_level > 0")
                       .find_each do |delivery|
        next if delivery.due_at.present? && delivery.due_at <= 24.hours.ago

        delivery.escalation_events.delete_all
        delivery.update!(escalation_level: 0, escalated_at: nil)
      end
    end

    def self.backfill_all!
      Tenant.find_each { |tenant| backfill!(tenant) }
    end
  end
end
