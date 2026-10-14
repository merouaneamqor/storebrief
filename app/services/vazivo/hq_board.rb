module Vazivo
  # Head-office today board: only what needs a decision — unconfirmed stores,
  # overdue work, and redo verdicts — plus one awareness tracker for the latest brief,
  # task completion % with drill-down by campaign and region, and module compliance
  # rollups (Tasks / Audits / Campaigns / Training / VM).
  class HqBoard
    SEVERITY = { "redo" => 0, "overdue" => 1, "unconfirmed" => 2 }.freeze

    # One critical exception row: store, campaign, age, assignee, deep link.
    Row = Struct.new(
      :store_name, :owner_name, :due_at, :tone, :status_label, :path, :kind, :priority,
      :campaign, :issue_opened_at, :age_seconds, :area_id, :area_name, :org_unit_id, :visit_id,
      keyword_init: true
    ) do
      def age_label
        return "-" if age_seconds.nil?

        hours = (age_seconds / 3600.0).floor
        if hours < 24
          I18n.t("morocco.hq.exception_age.hours", count: [ hours, 1 ].max)
        else
          I18n.t("morocco.hq.exception_age.days", count: [ (hours / 24.0).floor, 1 ].max)
        end
      end

      def visit_linked?
        visit_id.present?
      end
    end
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
    AreaOption = Struct.new(:id, :name, keyword_init: true)
    Snapshot = Struct.new(
      :unconfirmed, :overdue, :redo, :exceptions, :awareness_brief, :awareness_rollup,
      :podium, :store_status, :task_monitoring, :compliance_rollups,
      :areas, :area_id, keyword_init: true
    )

    def self.for(tenant, area_id: nil)
      new(tenant, area_id: area_id).snapshot
    end

    def initialize(tenant, area_id: nil)
      @tenant = tenant
      @area_id = area_id.presence&.to_i
    end

    def snapshot
      brief = latest_brief
      unconfirmed = filter_by_area(unconfirmed_rows(brief))
      overdue = filter_by_area(overdue_rows)
      redos = filter_by_area(redo_rows)
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
        compliance_rollups: build_compliance_rollups,
        areas: area_options,
        area_id: @area_id
      )
    end

    private

    def routes
      Rails.application.routes.url_helpers
    end

    # Urgency: severity first, then priority, then oldest issue age.
    def merge_exceptions(*lists)
      lists.flatten.sort_by do |row|
        [
          SEVERITY.fetch(row.kind, 9),
          Communication.priority_rank(row.priority),
          -(row.age_seconds || 0)
        ]
      end
    end

    def filter_by_area(rows)
      return rows if @area_id.blank?

      rows.select { |row| row.area_id == @area_id }
    end

    def area_options
      @tenant.org_units.areas.order(:name).map { |area| AreaOption.new(id: area.id, name: area.name) }
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
        opened_at = delivery.created_at || brief.created_at
        build_row(
          delivery: delivery,
          campaign: brief.title,
          status_label: I18n.t("morocco.awareness.steps.received"),
          tone: delivery.tone,
          kind: "unconfirmed",
          priority: brief.priority,
          issue_opened_at: opened_at,
          path: delivery_deep_link(brief, delivery),
          visit_id: brief.visit_id
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
          build_row(
            delivery: record,
            campaign: record.communication.title,
            status_label: record.communication.title,
            tone: "late",
            kind: "overdue",
            priority: record.communication.priority,
            issue_opened_at: record.due_at,
            path: delivery_deep_link(record.communication, record),
            visit_id: record.communication.visit_id
          )
        else
          build_row(
            delivery: record,
            campaign: record.checklist.title,
            status_label: record.checklist.title,
            tone: "late",
            kind: "overdue",
            priority: Communication::DEFAULT_PRIORITY,
            issue_opened_at: record.due_at,
            path: checklist_deep_link(record.checklist, record),
            visit_id: nil
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
        opened_at = delivery.validated_at || delivery.completed_at || delivery.updated_at
        build_row(
          delivery: delivery,
          campaign: delivery.communication.title,
          status_label: delivery.communication.title,
          tone: "urgent",
          kind: "redo",
          priority: delivery.communication.priority,
          issue_opened_at: opened_at,
          path: delivery_deep_link(delivery.communication, delivery),
          visit_id: delivery.communication.visit_id
        )
      end
    end

    def build_row(delivery:, campaign:, status_label:, tone:, kind:, priority:, issue_opened_at:, path:, visit_id:)
      area = area_for(delivery.org_unit)
      deep_path = visit_id.present? ? routes.visit_path(visit_id) : path
      Row.new(
        store_name: delivery.org_unit.name,
        owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
        due_at: delivery.due_at,
        tone: tone,
        status_label: status_label,
        path: deep_path,
        kind: kind,
        priority: priority,
        campaign: campaign,
        issue_opened_at: issue_opened_at,
        age_seconds: age_from(issue_opened_at),
        area_id: area&.id,
        area_name: area&.name || I18n.t("morocco.hq.exception_area.none"),
        org_unit_id: delivery.org_unit_id,
        visit_id: visit_id
      )
    end

    def delivery_deep_link(brief, delivery)
      routes.communication_path(brief, anchor: "store-#{delivery.org_unit_id}")
    end

    def checklist_deep_link(checklist, delivery)
      routes.checklist_path(checklist, anchor: "store-#{delivery.org_unit_id}")
    end

    def age_from(opened_at)
      return nil if opened_at.blank?

      [ (Time.current - opened_at).to_i, 0 ].max
    end

    def area_for(store)
      units = org_units_by_id
      current = units[store.parent_id]
      guard = 0
      while current && guard < 8
        return current if current.unit_type == "area"

        current = units[current.parent_id]
        guard += 1
      end
      nil
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
