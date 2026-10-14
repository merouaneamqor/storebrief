module Vazivo
  # Open tasks for the stores a person actually manages.
  # Store users see their store. Area users see descendant stores only.
  class MyTasks
    FILTERS = %w[overdue today upcoming].freeze

    Item = Struct.new(
      :id, :kind, :title, :store_name, :due_at, :priority, :tone, :record,
      keyword_init: true
    )

    def self.for(user:, tenant:, filter: nil)
      new(user, tenant).list(filter)
    end

    def self.find(user:, tenant:, id:, kind:)
      new(user, tenant).find(id, kind)
    end

    def initialize(user, tenant)
      @user = user
      @tenant = tenant
    end

    def list(filter)
      items = open_items
      items = items.select { |item| matches?(item, filter) } if FILTERS.include?(filter.to_s)
      items.sort_by { |item| sort_key(item) }
    end

    def find(id, kind)
      open_items.find { |item| item.id == id.to_i && item.kind == kind.to_s }
    end

    private

    def matches?(item, filter)
      record = item.record
      case filter.to_s
      when "overdue" then record.late?
      when "today" then record.due_today? && !record.late?
      when "upcoming" then record.due_at.present? && !record.late? && !record.due_today?
      else true
      end
    end

    def sort_key(item)
      [ Communication.priority_rank(item.priority), item.due_at || 100.years.from_now, item.title.to_s ]
    end

    def open_items
      brief_items + checklist_items
    end

    def store_ids
      @store_ids ||= managed_stores.pluck(:id)
    end

    def managed_stores
      if (store = @user.store_org_unit)
        @tenant.org_units.stores.where(id: store.id)
      elsif (area = @user.area_org_unit)
        area.descendant_stores.where(tenant_id: @tenant.id)
      elsif @user.hq? || @user.super_admin?
        @tenant.org_units.stores
      else
        OrgUnit.none
      end
    end

    def brief_items
      return [] if store_ids.empty?

      Delivery.current_instances
              .where(org_unit_id: store_ids, status: "pending")
              .where(communications: { tenant_id: @tenant.id, status: "sent", format: "task" })
              .includes(:communication, :org_unit)
              .map { |delivery| item_for_brief(delivery) }
    end

    def checklist_items
      return [] if store_ids.empty?

      ChecklistDelivery.joins(:checklist)
                       .where(org_unit_id: store_ids, status: "pending")
                       .where(checklists: { tenant_id: @tenant.id, status: "sent" })
                       .includes(:checklist, :org_unit)
                       .map { |delivery| item_for_check(delivery) }
    end

    def item_for_brief(delivery)
      Item.new(
        id: delivery.id,
        kind: "task",
        title: delivery.communication.title,
        store_name: delivery.org_unit.name,
        due_at: delivery.due_at,
        priority: delivery.communication.priority,
        tone: delivery.tone,
        record: delivery
      )
    end

    def item_for_check(delivery)
      Item.new(
        id: delivery.id,
        kind: "checklist",
        title: delivery.checklist.title,
        store_name: delivery.org_unit.name,
        due_at: delivery.due_at,
        priority: Communication::DEFAULT_PRIORITY,
        tone: delivery.tone,
        record: delivery
      )
    end
  end
end
