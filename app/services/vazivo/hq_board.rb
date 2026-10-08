module Vazivo
  # Head-office today board: only what needs a decision — unconfirmed stores,
  # overdue work, and redo verdicts — plus one awareness tracker for the latest brief.
  class HqBoard
    SEVERITY = { "redo" => 0, "overdue" => 1, "unconfirmed" => 2 }.freeze

    Row = Struct.new(:store_name, :owner_name, :due_at, :tone, :status_label, :path, :kind, :priority, keyword_init: true)
    Trend = Struct.new(:points, :span, :from, :to, :delta, keyword_init: true)
    Spark = Struct.new(:points, :delta, keyword_init: true)
    ActivityItem = Struct.new(:text, :at, :path, :kind, keyword_init: true)
    Snapshot = Struct.new(
      :unconfirmed, :overdue, :redo, :exceptions, :awareness_brief, :awareness_rollup,
      :podium, :store_status, :trend, :sparks, :leaders, :activity, keyword_init: true
    )

    def self.for(tenant)
      new(tenant).snapshot
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def snapshot
      brief = latest_brief
      unconfirmed = unconfirmed_rows(brief)
      overdue = overdue_rows
      redos = redo_rows
      ranking = Ranking.for(@tenant)
      Snapshot.new(
        unconfirmed: unconfirmed,
        overdue: overdue,
        redo: redos,
        exceptions: merge_exceptions(unconfirmed, overdue, redos),
        awareness_brief: brief,
        awareness_rollup: brief ? Delivery.awareness_rollup(brief.deliveries) : nil,
        podium: ranking.podium,
        store_status: StoreStatus.for(@tenant),
        trend: build_trend,
        sparks: build_sparks,
        leaders: ranking.rows.first(5),
        activity: activity_items
      )
    end

    private

    def merge_exceptions(*lists)
      lists.flatten.sort_by do |row|
        [ SEVERITY.fetch(row.kind, 9), Communication.priority_rank(row.priority), row.due_at || Time.at(0) ]
      end
    end

    def latest_brief
      @tenant.communications.sent
             .includes(deliveries: [ :org_unit, :assignee ])
             .order(created_at: :desc)
             .first
    end

    def unconfirmed_rows(brief)
      return [] unless brief

      brief.deliveries.select { |d| d.awareness == "pending" }.map do |delivery|
        Row.new(
          store_name: delivery.org_unit.name,
          owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
          due_at: delivery.due_at,
          tone: delivery.tone,
          status_label: I18n.t("morocco.awareness.steps.received"),
          path: Rails.application.routes.url_helpers.communication_path(brief),
          kind: "unconfirmed",
          priority: brief.priority
        )
      end
    end

    def overdue_rows
      routes = Rails.application.routes.url_helpers
      briefs = Delivery.joins(:communication)
                       .includes(:org_unit, :assignee, :communication)
                       .where(communications: { tenant_id: @tenant.id, status: "sent" })
                       .where.not(status: %w[completed read])
                       .where.not(due_at: nil)
                       .where("deliveries.due_at < ?", Time.current)
      checks = ChecklistDelivery.joins(:checklist)
                                .includes(:org_unit, :assignee, :checklist)
                                .where(checklists: { tenant_id: @tenant.id, status: "sent" })
                                .where.not(status: "completed")
                                .where.not(due_at: nil)
                                .where("checklist_deliveries.due_at < ?", Time.current)

      records = (briefs.to_a + checks.to_a).sort_by do |record|
        [ record.is_a?(Delivery) ? record.communication.priority_rank : Communication.priority_rank(nil), record.due_at ]
      end
      records.first(12).map do |record|
        if record.is_a?(Delivery)
          Row.new(
            store_name: record.org_unit.name,
            owner_name: record.assignee&.name || I18n.t("morocco.owner.unassigned"),
            due_at: record.due_at,
            tone: "late",
            status_label: record.communication.title,
            path: routes.communication_path(record.communication),
            kind: "overdue",
            priority: record.communication.priority
          )
        else
          Row.new(
            store_name: record.org_unit.name,
            owner_name: record.assignee&.name || I18n.t("morocco.owner.unassigned"),
            due_at: record.due_at,
            tone: "late",
            status_label: record.checklist.title,
            path: routes.checklist_path(record.checklist),
            kind: "overdue",
            priority: Communication::DEFAULT_PRIORITY
          )
        end
      end
    end

    def build_trend
      today = Schedule.now.to_date
      from = today.beginning_of_month
      to = today.end_of_month
      counts = completion_counts([ today - 13, from ].min, today)
      Trend.new(
        points: (from..today).map { |day| counts.fetch(day, 0) },
        span: (to - from).to_i + 1,
        from: from,
        to: to,
        delta: window_delta(counts, today)
      )
    end

    def build_sparks
      today = Schedule.now.to_date
      from = today - 13
      {
        "on_track" => spark_for(completion_counts(from, today), from, today),
        "attention" => spark_for(created_counts(from, today), from, today),
        "critical" => spark_for(overdue_counts(from, today), from, today),
        "decisions" => spark_for(decision_counts(from, today), from, today)
      }
    end

    def spark_for(counts, from, today)
      Spark.new(
        points: (from..today).map { |day| counts.fetch(day, 0) },
        delta: window_delta(counts, today)
      )
    end

    def window_delta(counts, today)
      current = (0..6).sum { |offset| counts.fetch(today - offset, 0) }
      previous = (7..13).sum { |offset| counts.fetch(today - offset, 0) }
      return nil if previous.zero?

      (((current - previous).to_f / previous) * 100).round(1)
    end

    def completion_counts(from_date, to_date)
      range = zone_range(from_date, to_date)
      merge_tallies(
        tally_times(sent_deliveries.where(deliveries: { completed_at: range }).pluck("deliveries.completed_at")),
        tally_times(sent_checks.where(checklist_deliveries: { completed_at: range }).pluck("checklist_deliveries.completed_at"))
      )
    end

    def created_counts(from_date, to_date)
      range = zone_range(from_date, to_date)
      merge_tallies(
        tally_times(sent_deliveries.where(deliveries: { created_at: range }).pluck("deliveries.created_at")),
        tally_times(sent_checks.where(checklist_deliveries: { created_at: range }).pluck("checklist_deliveries.created_at"))
      )
    end

    def overdue_counts(from_date, to_date)
      range = zone_range(from_date, to_date)
      now = Time.current
      merge_tallies(
        tally_times(
          sent_deliveries.where.not(deliveries: { status: %w[completed read] })
                         .where(deliveries: { due_at: range })
                         .where("deliveries.due_at < ?", now)
                         .pluck("deliveries.due_at")
        ),
        tally_times(
          sent_checks.where.not(checklist_deliveries: { status: "completed" })
                     .where(checklist_deliveries: { due_at: range })
                     .where("checklist_deliveries.due_at < ?", now)
                     .pluck("checklist_deliveries.due_at")
        )
      )
    end

    def decision_counts(from_date, to_date)
      range = zone_range(from_date, to_date)
      merge_tallies(
        tally_times(sent_deliveries.where(deliveries: { awareness: "pending", created_at: range }).pluck("deliveries.created_at")),
        tally_times(sent_deliveries.where(deliveries: { verdict: "non_conforme", validated_at: range }).pluck("deliveries.validated_at"))
      )
    end

    def sent_deliveries
      Delivery.joins(:communication).where(communications: { tenant_id: @tenant.id, status: "sent" })
    end

    def sent_checks
      ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: @tenant.id, status: "sent" })
    end

    def zone_range(from_date, to_date)
      zone = Schedule::ZONE
      zone.local(from_date.year, from_date.month, from_date.day)..zone.local(to_date.year, to_date.month, to_date.day).end_of_day
    end

    def tally_times(times)
      zone = Schedule::ZONE
      Array(times).each_with_object(Hash.new(0)) do |time, tally|
        next if time.blank?

        tally[time.in_time_zone(zone).to_date] += 1
      end
    end

    def merge_tallies(*tallies)
      tallies.each_with_object(Hash.new(0)) do |tally, merged|
        tally.each { |day, count| merged[day] += count }
      end
    end

    def activity_items
      routes = Rails.application.routes.url_helpers
      delivery_ids = sent_deliveries.order("deliveries.updated_at DESC").limit(6).pluck("deliveries.id")
      check_ids = sent_checks.order("checklist_deliveries.updated_at DESC").limit(4).pluck("checklist_deliveries.id")
      deliveries = Delivery.includes(:org_unit, :communication).where(id: delivery_ids)
      checks = ChecklistDelivery.includes(:org_unit, :checklist).where(id: check_ids)
      items = deliveries.map { |delivery| activity_from_delivery(delivery, routes) }
      items += checks.map { |delivery| activity_from_check(delivery, routes) }
      items.sort_by { |item| item.at || Time.zone.at(0) }.reverse.first(5)
    end

    def activity_from_delivery(delivery, routes)
      kind =
        if delivery.verdict == "non_conforme"
          "redo"
        elsif delivery.finished?
          "done"
        else
          "open"
        end
      ActivityItem.new(
        text: I18n.t("morocco.hq.activity_#{kind}", store: delivery.org_unit.name, title: delivery.communication.title),
        at: delivery.updated_at,
        path: routes.communication_path(delivery.communication),
        kind: kind
      )
    end

    def activity_from_check(delivery, routes)
      kind = delivery.finished? ? "check_done" : "check"
      ActivityItem.new(
        text: I18n.t("morocco.hq.activity_#{kind}", store: delivery.org_unit.name, title: delivery.checklist.title),
        at: delivery.updated_at,
        path: routes.checklist_path(delivery.checklist),
        kind: kind
      )
    end

    def redo_rows
      Delivery.joins(:communication)
              .includes(:org_unit, :assignee, :communication)
              .where(communications: { tenant_id: @tenant.id })
              .where(verdict: "non_conforme")
              .order(validated_at: :desc)
              .limit(8)
              .map do |delivery|
        Row.new(
          store_name: delivery.org_unit.name,
          owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
          due_at: delivery.due_at,
          tone: "urgent",
          status_label: delivery.communication.title,
          path: Rails.application.routes.url_helpers.communication_path(delivery.communication),
          kind: "redo",
          priority: delivery.communication.priority
        )
      end
    end
  end
end
