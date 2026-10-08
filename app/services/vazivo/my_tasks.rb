module Vazivo
  # Per-user open work across the stores the user can see, with due-date filters.
  class MyTasks
    FILTERS = %w[all overdue today upcoming].freeze

    Snapshot = Struct.new(:filter, :items, keyword_init: true)

    def self.for(user:, tenant:, filter: "all")
      new(user, tenant, filter).snapshot
    end

    def initialize(user, tenant, filter)
      @user = user
      @tenant = tenant
      @filter = FILTERS.include?(filter.to_s) ? filter.to_s : "all"
    end

    def snapshot
      records = apply_filter(open_records)
      Snapshot.new(filter: @filter, items: records.map { |record| to_item(record) })
    end

    private

    def open_records
      ids = store_ids
      return [] if ids.empty?

      deliveries = Delivery.current_instances
                           .joins(:communication)
                           .where(org_unit_id: ids, assignee_id: @user.id, communications: { tenant_id: @tenant.id, status: "sent" })
                           .where.not(status: %w[completed read])
                           .includes(:communication, :org_unit)
      checks = ChecklistDelivery.joins(:checklist)
                                .where(org_unit_id: ids, assignee_id: @user.id, checklists: { tenant_id: @tenant.id, status: "sent" })
                                .where.not(status: "completed")
                                .includes(:checklist, :org_unit)
      sort_records(deliveries.to_a + checks.to_a)
    end

    def store_ids
      if (store = @user.store_org_unit)
        [ store.id ]
      elsif (area = @user.area_org_unit)
        area.descendant_stores.pluck(:id)
      else
        []
      end
    end

    def apply_filter(records)
      case @filter
      when "overdue"
        records.select(&:late?)
      when "today"
        records.select { |record| record.due_today? && !record.late? }
      when "upcoming"
        records.select { |record| upcoming?(record) }
      else
        records
      end
    end

    def upcoming?(record)
      return false if record.finished? || record.late? || record.due_at.blank?

      record.due_at.in_time_zone(Schedule::ZONE).to_date > Schedule.now.to_date
    end

    def sort_records(records)
      records.sort_by do |record|
        rank = record.late? ? 0 : (record.urgent? ? 1 : (record.due_today? ? 2 : 3))
        priority = record.is_a?(Delivery) ? record.communication.priority_rank : Communication.priority_rank(nil)
        [ priority, rank, record.due_at || 100.years.from_now ]
      end
    end

    def to_item(record)
      routes = Rails.application.routes.url_helpers
      if record.is_a?(Delivery)
        step = record.next_awareness_step
        Radar::Item.new(
          kind: "brief",
          title: record.communication.title,
          due_at: record.due_at,
          tone: record.tone,
          path: routes.inbox_path(record),
          store_name: record.org_unit.name,
          escalation_level: record.escalation_level.to_i,
          next_step: step,
          next_label: step ? I18n.t("morocco.awareness.actions.#{step}") : nil,
          record_id: record.id,
          priority: record.communication.priority
        )
      else
        Radar::Item.new(
          kind: "checklist",
          title: record.checklist.title,
          due_at: record.due_at,
          tone: record.tone,
          path: routes.checklists_delivery_path(record),
          store_name: record.org_unit.name,
          escalation_level: record.escalation_level.to_i,
          next_step: nil,
          next_label: I18n.t("morocco.radar.open_routine"),
          record_id: record.id,
          priority: Communication::DEFAULT_PRIORITY
        )
      end
    end
  end
end
