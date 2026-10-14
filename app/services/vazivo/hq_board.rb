module Vazivo
  # Head-office today board: only what needs a decision — unconfirmed stores,
  # overdue work, and redo verdicts — plus one awareness tracker for the latest brief,
  # task completion % with drill-down by campaign and region, and module compliance
  # rollups (Tasks / Audits / Campaigns / Training / VM).
  class HqBoard
    SEVERITY = { "redo" => 0, "overdue" => 1, "unconfirmed" => 2 }.freeze

    Row = Struct.new(:store_name, :owner_name, :due_at, :tone, :status_label, :path, :kind, :priority, keyword_init: true)
    StoreProgress = Struct.new(
      :store_name, :owner_name, :due_at, :tone, :finished, :overdue, :path, keyword_init: true
    )
    MonitorGroup = Struct.new(
      :id, :label, :total, :done, :overdue, :percent, :stores, :path, keyword_init: true
    )
    TaskMonitoring = Struct.new(
      :total, :done, :overdue, :percent, :by_campaign, :by_region, keyword_init: true
    ) do
      def any?
        total.positive?
      end
    end
    # One module card on the HQ compliance strip. percent is nil when empty or
    # the module is not shipped yet — views must render "-" not "0%".
    ModuleRollup = Struct.new(
      :key, :percent, :done, :total, :available, :path, keyword_init: true
    ) do
      def display_percent
        percent.nil? ? "-" : "#{percent}%"
      end

      def present?
        available && !percent.nil?
      end
    end
    ComplianceRollups = Struct.new(:modules, keyword_init: true) do
      def [](key)
        modules.find { |mod| mod.key == key.to_s }
      end

      def each(&block) = modules.each(&block)
    end
    Snapshot = Struct.new(
      :unconfirmed, :overdue, :redo, :exceptions, :awareness_brief, :awareness_rollup,
      :podium, :store_status, :task_monitoring, :compliance_rollups, keyword_init: true
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
      Snapshot.new(
        unconfirmed: unconfirmed,
        overdue: overdue,
        redo: redos,
        exceptions: merge_exceptions(unconfirmed, overdue, redos),
        awareness_brief: brief,
        awareness_rollup: brief ? Delivery.awareness_rollup(brief.deliveries) : nil,
        podium: Ranking.for(@tenant).podium.first(3),
        store_status: StoreStatus.for(@tenant),
        task_monitoring: build_task_monitoring,
        compliance_rollups: build_compliance_rollups
      )
    end

    private

    def routes
      Rails.application.routes.url_helpers
    end

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
          path: routes.communication_path(brief),
          kind: "unconfirmed",
          priority: brief.priority
        )
      end
    end

    def overdue_rows
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
          path: routes.communication_path(delivery.communication),
          kind: "redo",
          priority: delivery.communication.priority
        )
      end
    end

    # Network compliance % per module for the HQ strip. Empty or unshipped modules
    # keep percent nil so the board shows "-" rather than a misleading 0.
    def build_compliance_rollups
      ComplianceRollups.new(
        modules: [
          tasks_rollup,
          audits_rollup,
          campaigns_rollup,
          unavailable_rollup("training"),
          unavailable_rollup("vm", path: routes.ranking_path)
        ]
      )
    end

    def tasks_rollup
      week = Schedule.now.all_week
      scope = Delivery.joins(:communication)
                      .where(communications: { tenant_id: @tenant.id, status: "sent", format: "task" })
                      .where(created_at: week)
      total = scope.count
      return empty_rollup("tasks", path: routes.app_root_path) if total.zero?

      done = scope.where(status: %w[completed read]).count
      ModuleRollup.new(
        key: "tasks",
        percent: percent_of(done, total),
        done: done,
        total: total,
        available: true,
        path: routes.app_root_path
      )
    end

    def audits_rollup
      week = Schedule.now.all_week
      scores = Delivery.joins(:communication)
                       .where(communications: { tenant_id: @tenant.id, status: "sent" })
                       .where.not(score: nil)
                       .where("COALESCE(deliveries.validated_at, deliveries.completed_at, deliveries.created_at) BETWEEN ? AND ?", week.begin, week.end)
                       .pluck(:score)
      return empty_rollup("audits", path: routes.audit_history_path) if scores.empty?

      avg = (scores.sum.to_f / scores.size).round
      ModuleRollup.new(
        key: "audits",
        percent: avg,
        done: scores.size,
        total: scores.size,
        available: true,
        path: routes.audit_history_path
      )
    end

    def campaigns_rollup
      snapshot = CampaignDashboard.for(@tenant)
      return empty_rollup("campaigns", path: routes.campaigns_playbooks_path) if snapshot.total.zero?

      ModuleRollup.new(
        key: "campaigns",
        percent: snapshot.percent,
        done: snapshot.done,
        total: snapshot.total,
        available: true,
        path: routes.campaigns_playbooks_path
      )
    end

    def unavailable_rollup(key, path: nil)
      ModuleRollup.new(key: key, percent: nil, done: 0, total: 0, available: false, path: path)
    end

    def empty_rollup(key, path: nil)
      ModuleRollup.new(key: key, percent: nil, done: 0, total: 0, available: true, path: path)
    end

    # Live sent tasks (still have at least one open store): completion % and overdue
    # by campaign and by region, with store drill-down rows.
    def build_task_monitoring
      deliveries = live_task_deliveries
      return empty_task_monitoring if deliveries.empty?

      done = deliveries.count(&:finished?)
      overdue = deliveries.count(&:late?)
      TaskMonitoring.new(
        total: deliveries.size,
        done: done,
        overdue: overdue,
        percent: percent_of(done, deliveries.size),
        by_campaign: groups_by_campaign(deliveries),
        by_region: groups_by_region(deliveries)
      )
    end

    def empty_task_monitoring
      TaskMonitoring.new(total: 0, done: 0, overdue: 0, percent: 0, by_campaign: [], by_region: [])
    end

    def live_task_deliveries
      live_ids = Delivery.joins(:communication)
                         .where(communications: { tenant_id: @tenant.id, status: "sent", format: "task" })
                         .where(status: "pending")
                         .distinct
                         .pluck(:communication_id)
      return [] if live_ids.empty?

      Delivery.joins(:communication)
              .includes(:org_unit, :assignee, :communication)
              .where(communication_id: live_ids)
              .order("communications.created_at DESC", :id)
              .to_a
    end

    def groups_by_campaign(deliveries)
      deliveries.group_by(&:communication).map do |brief, rows|
        build_group(
          id: "campaign-#{brief.id}",
          label: brief.title,
          rows: rows,
          path: routes.communication_path(brief)
        )
      end.sort_by { |group| [ -group.overdue, group.percent, group.label ] }
    end

    def groups_by_region(deliveries)
      units = org_units_by_id
      deliveries.group_by { |delivery| region_name_for(delivery.org_unit, units) }.map do |name, rows|
        build_group(
          id: "region-#{name.parameterize}",
          label: name,
          rows: rows,
          path: nil
        )
      end.sort_by { |group| [ -group.overdue, group.percent, group.label ] }
    end

    def build_group(id:, label:, rows:, path:)
      done = rows.count(&:finished?)
      overdue = rows.count(&:late?)
      MonitorGroup.new(
        id: id,
        label: label,
        total: rows.size,
        done: done,
        overdue: overdue,
        percent: percent_of(done, rows.size),
        stores: store_progress_rows(rows),
        path: path
      )
    end

    def store_progress_rows(rows)
      rows.sort_by { |row| [ row.finished? ? 1 : 0, row.late? ? 0 : 1, row.org_unit.name ] }.map do |delivery|
        StoreProgress.new(
          store_name: delivery.org_unit.name,
          owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
          due_at: delivery.due_at,
          tone: delivery.tone,
          finished: delivery.finished?,
          overdue: delivery.late?,
          path: routes.communication_path(delivery.communication, anchor: "store-#{delivery.org_unit_id}")
        )
      end
    end

    def org_units_by_id
      @org_units_by_id ||= @tenant.org_units.index_by(&:id)
    end

    def region_name_for(store, units)
      current = units[store.parent_id]
      guard = 0
      while current && guard < 8
        return current.name if current.unit_type == "region"

        current = units[current.parent_id]
        guard += 1
      end
      I18n.t("morocco.hq.monitoring.unassigned_region")
    end

    def percent_of(done, total)
      return 0 if total.zero?

      ((done.to_f / total) * 100).round
    end
  end
end
