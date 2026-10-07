module Vazivo
  # Morning screen for a store or area manager: what is due now, what can wait,
  # and which neighbouring stores have not confirmed the latest instruction.
  class Radar
    Item = Struct.new(
      :kind, :title, :due_at, :tone, :path, :store_name, :escalation_level,
      :next_step, :next_label, :record_id, keyword_init: true
    )
    Snapshot = Struct.new(
      :lens, :greeting_key, :name, :place_name, :ramadan, :opens_at,
      :urgent_count, :late_count, :done_count, :now_items, :later_items,
      :attention_count, :attention_names, :campaign_title,
      keyword_init: true
    )

    def self.for(user:, tenant:)
      new(user, tenant).snapshot
    end

    def initialize(user, tenant)
      @user = user
      @tenant = tenant
    end

    def snapshot
      if (store = @user.store_org_unit)
        build(lens: "store", place: store.name, stores: [ store ], attention_stores: siblings_of(store))
      elsif (area = @user.area_org_unit)
        stores = area.descendant_stores.to_a
        build(lens: "area", place: area.name, stores: stores, attention_stores: stores)
      else
        empty("store")
      end
    end

    private

    def build(lens:, place:, stores:, attention_stores:)
      open_items = open_records(stores)
      now_records, later_records = open_items.partition(&:now?)
      campaign_title, names = unconfirmed(attention_stores)
      Snapshot.new(
        lens: lens,
        greeting_key: Schedule.now.hour < 17 ? "morning" : "evening",
        name: @user.name.to_s.split.first,
        place_name: place,
        ramadan: @tenant.ramadan_mode?,
        opens_at: @tenant.effective_open,
        urgent_count: open_items.count(&:urgent?),
        late_count: open_items.count(&:late?),
        done_count: done_today(stores),
        now_items: now_records.first(8).map { |record| to_item(record) },
        later_items: later_records.first(8).map { |record| to_item(record) },
        attention_count: names.size,
        attention_names: names,
        campaign_title: campaign_title
      )
    end

    def empty(lens)
      Snapshot.new(
        lens: lens,
        greeting_key: "morning",
        name: @user.name.to_s.split.first,
        place_name: nil,
        ramadan: @tenant.ramadan_mode?,
        opens_at: @tenant.effective_open,
        urgent_count: 0,
        late_count: 0,
        done_count: 0,
        now_items: [],
        later_items: [],
        attention_count: 0,
        attention_names: [],
        campaign_title: nil
      )
    end

    def open_records(stores)
      ids = stores.map(&:id)
      return [] if ids.empty?

      deliveries = Delivery.joins(:communication)
                           .where(org_unit_id: ids, communications: { tenant_id: @tenant.id, status: "sent" })
                           .where.not(status: %w[completed read])
                           .includes(:communication, :org_unit)
      checks = ChecklistDelivery.joins(:checklist)
                                .where(org_unit_id: ids, checklists: { tenant_id: @tenant.id, status: "sent" })
                                .where.not(status: "completed")
                                .includes(:checklist, :org_unit)
      (deliveries.to_a + checks.to_a).sort_by do |record|
        rank = record.late? ? 0 : (record.urgent? ? 1 : (record.due_today? ? 2 : 3))
        [ rank, record.due_at || 100.years.from_now ]
      end
    end

    def done_today(stores)
      ids = stores.map(&:id)
      return 0 if ids.empty?

      day = Schedule.now.all_day
      briefs = Delivery.joins(:communication)
                       .where(org_unit_id: ids, communications: { tenant_id: @tenant.id })
                       .where(status: %w[completed read], completed_at: day)
                       .count
      checks = ChecklistDelivery.joins(:checklist)
                                .where(org_unit_id: ids, checklists: { tenant_id: @tenant.id })
                                .where(status: "completed", completed_at: day)
                                .count
      briefs + checks
    end

    def unconfirmed(stores)
      return [ nil, [] ] if stores.empty?

      campaign = @tenant.communications.sent.where(source: "playbook").order(created_at: :desc).first
      campaign ||= @tenant.communications.sent.order(created_at: :desc).first
      return [ nil, [] ] unless campaign

      pending_ids = campaign.deliveries.where(org_unit_id: stores.map(&:id), awareness: "pending").pluck(:org_unit_id)
      names = stores.select { |store| pending_ids.include?(store.id) }.map(&:name)
      [ campaign.title, names ]
    end

    def siblings_of(store)
      parent = store.parent
      return [] if parent.blank?

      parent.descendant_stores.where.not(id: store.id).to_a
    end

    def to_item(record)
      routes = Rails.application.routes.url_helpers
      if record.is_a?(Delivery)
        step = record.next_awareness_step
        Item.new(
          kind: "brief",
          title: record.communication.title,
          due_at: record.due_at,
          tone: record.tone,
          path: routes.inbox_path(record),
          store_name: record.org_unit.name,
          escalation_level: record.escalation_level.to_i,
          next_step: step,
          next_label: step ? I18n.t("morocco.awareness.actions.#{step}") : nil,
          record_id: record.id
        )
      else
        Item.new(
          kind: "checklist",
          title: record.checklist.title,
          due_at: record.due_at,
          tone: record.tone,
          path: routes.checklists_delivery_path(record),
          store_name: record.org_unit.name,
          escalation_level: record.escalation_level.to_i,
          next_step: nil,
          next_label: I18n.t("morocco.radar.open_routine"),
          record_id: record.id
        )
      end
    end
  end
end
