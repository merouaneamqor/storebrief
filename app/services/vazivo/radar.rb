module Vazivo
  # Morning screen for a store or area manager: what is due now, what can wait,
  # and which neighbouring stores have not confirmed the latest instruction.
  class Radar
    Item = Struct.new(
      :kind, :title, :due_at, :tone, :path, :store_name, :escalation_level,
      :next_step, :next_label, :record_id, :priority, keyword_init: true
    )
    Snapshot = Struct.new(
      :lens, :greeting_key, :name, :place_name, :ramadan, :opens_at,
      :urgent_count, :late_count, :done_count, :now_items, :later_items,
      :attention_count, :attention_names, :campaign_title, :area,
      keyword_init: true
    )
    # Monitoring summary for an area or region manager (read only).
    StoreRow = Struct.new(:store, :score, :status, keyword_init: true)
    AreaSummary = Struct.new(
      :stores_count, :compliance_percent, :tasks_done, :tasks_total, :tasks_open, :tasks_late,
      :audits, :campaign, :attention_stores, :store_rows,
      keyword_init: true
    ) do
      def sorted_store_rows(sort)
        rows = Array(store_rows)
        case sort.to_s
        when "score_asc"
          rows.sort_by { |row| [ row.score.nil? ? 1 : 0, row.score.to_i, row.store.name ] }
        when "name"
          rows.sort_by { |row| row.store.name }
        else
          rows.sort_by { |row| [ row.score.nil? ? 1 : 0, -(row.score || 0), row.store.name ] }
        end
      end
    end
    Campaign = Struct.new(:title, :received, :total, :percent, keyword_init: true)
    AttentionStore = Struct.new(:name, :reasons, :late_count, :redo_count, :unconfirmed, keyword_init: true) do
      def count_for(reason)
        reason == :unconfirmed ? 1 : public_send("#{reason}_count")
      end
    end
    ATTENTION_LIMIT = 8

    def self.for(user:, tenant:)
      new(user, tenant).snapshot
    end

    def self.for_store(user:, tenant:, store:)
      new(user, tenant).store_snapshot(store)
    end

    def initialize(user, tenant)
      @user = user
      @tenant = tenant
    end

    def store_snapshot(store)
      build(lens: "store", place: store.name, stores: [ store ], attention_stores: siblings_of(store))
    end

    def snapshot
      if (store = @user.store_org_unit)
        build(lens: "store", place: store.name, stores: [ store ], attention_stores: siblings_of(store))
      elsif (area = @user.area_org_unit)
        stores = area.descendant_stores.to_a
        build(lens: "area", place: area.name, stores: stores, attention_stores: stores, area_summary: true)
      else
        empty("store")
      end
    end

    private

    def build(lens:, place:, stores:, attention_stores:, area_summary: false)
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
        campaign_title: campaign_title,
        area: area_summary ? area_summary_for(stores, open_items) : nil
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
        campaign_title: nil,
        area: nil
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
      # Task priority first (urgent, important, routine), then lateness, then deadline.
      (deliveries.to_a + checks.to_a).sort_by do |record|
        rank = record.late? ? 0 : (record.urgent? ? 1 : (record.due_today? ? 2 : 3))
        [ priority_rank_for(record), rank, record.due_at || 100.years.from_now ]
      end
    end

    # Checklists carry no priority, so they sort as routine.
    def priority_rank_for(record)
      record.is_a?(Delivery) ? record.communication.priority_rank : Communication.priority_rank(Communication::DEFAULT_PRIORITY)
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

      campaign = latest_campaign
      return [ nil, [] ] unless campaign

      pending_ids = campaign.deliveries.where(org_unit_id: stores.map(&:id), awareness: "pending").pluck(:org_unit_id)
      names = stores.select { |store| pending_ids.include?(store.id) }.map(&:name)
      [ campaign.title, names ]
    end

    # Everything below is computed from the area's own store ids only,
    # so a manager never sees figures from a neighbouring area.
    def area_summary_for(stores, open_items)
      ids = stores.map(&:id)
      done, total = compliance_totals(ids)
      AreaSummary.new(
        stores_count: ids.size,
        compliance_percent: total.zero? ? nil : ((done.to_f / total) * 100).round,
        tasks_done: done,
        tasks_total: total,
        tasks_open: open_items.size,
        tasks_late: open_items.count(&:late?),
        audits: audit_counts(ids),
        campaign: campaign_progress(ids),
        attention_stores: attention_rows(stores, open_items),
        store_rows: store_rows_for(stores)
      )
    end

    def store_rows_for(stores)
      scores = Ranking.for(@tenant).rows.index_by { |row| row.store.id }
      status_for = store_status_index
      stores.map do |store|
        StoreRow.new(
          store: store,
          score: scores[store.id]&.percent,
          status: status_for.fetch(store.id, "on_track")
        )
      end
    end

    def store_status_index
      result = StoreStatus.for(@tenant)
      StoreStatus::BUCKETS.each_with_object({}) do |bucket, index|
        result.stores(bucket).each { |store| index[store.id] = bucket }
      end
    end

    def compliance_totals(ids)
      rows = Ranking.for(@tenant).rows.select { |row| ids.include?(row.store.id) }
      [ rows.sum(&:done), rows.sum(&:total) ]
    end

    def audit_counts(ids)
      return { "conforme" => 0, "improve" => 0, "non_conforme" => 0, awaiting: 0 } if ids.empty?

      week = Schedule.now.all_week
      scope = Delivery.joins(:communication).where(org_unit_id: ids, communications: { tenant_id: @tenant.id })
      verdicts = scope.where(validated_at: week, verdict: Delivery::VERDICTS).group(:verdict).count
      Delivery::VERDICTS.index_with { |verdict| verdicts.fetch(verdict, 0) }
                        .merge(awaiting: scope.where(status: %w[completed read], completed_at: week, verdict: nil).count)
    end

    def campaign_progress(ids)
      campaign = latest_campaign
      return if campaign.nil? || ids.empty?

      deliveries = campaign.deliveries.where(org_unit_id: ids).to_a
      return if deliveries.empty?

      received = deliveries.count { |delivery| delivery.awareness != "pending" }
      Campaign.new(
        title: campaign.title,
        received: received,
        total: deliveries.size,
        percent: ((received.to_f / deliveries.size) * 100).round
      )
    end

    def attention_rows(stores, open_items)
      late = open_items.select(&:late?).group_by(&:org_unit_id).transform_values(&:size)
      redone = redo_counts(stores.map(&:id))
      _title, unconfirmed_names = unconfirmed(stores)
      rows = stores.filter_map do |store|
        unconfirmed = unconfirmed_names.include?(store.name)
        counts = { late: late.fetch(store.id, 0), redo: redone.fetch(store.id, 0) }
        reasons = counts.select { |_reason, count| count.positive? }.keys
        reasons << :unconfirmed if unconfirmed
        next if reasons.empty?

        AttentionStore.new(
          name: store.name, reasons: reasons, late_count: counts[:late],
          redo_count: counts[:redo], unconfirmed: unconfirmed
        )
      end
      rows.sort_by { |row| [ -(row.redo_count * 3 + row.late_count * 2 + (row.unconfirmed ? 1 : 0)), row.name ] }
          .first(ATTENTION_LIMIT)
    end

    def redo_counts(ids)
      return {} if ids.empty?

      Delivery.joins(:communication)
              .where(org_unit_id: ids, communications: { tenant_id: @tenant.id })
              .where(verdict: "non_conforme", status: "pending")
              .group(:org_unit_id).count
    end

    def latest_campaign
      @tenant.communications.sent.where(source: "playbook").order(created_at: :desc).first ||
        @tenant.communications.sent.order(created_at: :desc).first
    end

    def siblings_of(store)
      parent = store.parent
      return [] if parent.blank?

      parent.descendant_stores.where.not(id: store.id).to_a
    end

    # Inbox and checklist completion belong to the store user. Area and HQ
    # viewers still see the work, without a path they cannot open.
    def viewer_owns?(record)
      @user.store_org_unit&.id == record.org_unit_id
    end

    def to_item(record)
      routes = Rails.application.routes.url_helpers
      owned = viewer_owns?(record)
      if record.is_a?(Delivery)
        step = owned ? record.next_awareness_step : nil
        Item.new(
          kind: "brief",
          title: record.communication.title,
          due_at: record.due_at,
          tone: record.tone,
          path: (routes.inbox_path(record) if owned),
          store_name: record.org_unit.name,
          escalation_level: record.escalation_level.to_i,
          next_step: step,
          next_label: (I18n.t("morocco.awareness.actions.#{step}") if step),
          record_id: record.id,
          priority: record.communication.priority
        )
      else
        Item.new(
          kind: "checklist",
          title: record.checklist.title,
          due_at: record.due_at,
          tone: record.tone,
          path: (routes.checklists_delivery_path(record) if owned),
          store_name: record.org_unit.name,
          escalation_level: record.escalation_level.to_i,
          next_step: nil,
          next_label: (I18n.t("morocco.radar.open_routine") if owned),
          record_id: record.id,
          priority: Communication::DEFAULT_PRIORITY
        )
      end
    end
  end
end
