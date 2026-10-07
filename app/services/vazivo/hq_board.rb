module Vazivo
  # Head-office today board: only what needs a decision — unconfirmed stores,
  # overdue work, and redo verdicts — plus one awareness tracker for the latest brief.
  class HqBoard
    SEVERITY = { "redo" => 0, "overdue" => 1, "unconfirmed" => 2 }.freeze

    Row = Struct.new(:store_name, :owner_name, :due_at, :tone, :status_label, :path, :kind, keyword_init: true)
    Snapshot = Struct.new(
      :unconfirmed, :overdue, :redo, :exceptions, :awareness_brief, :awareness_rollup,
      :podium, :store_status, keyword_init: true
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
        store_status: StoreStatus.for(@tenant)
      )
    end

    private

    def merge_exceptions(*lists)
      lists.flatten.sort_by do |row|
        [ SEVERITY.fetch(row.kind, 9), row.due_at || Time.at(0) ]
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
          kind: "unconfirmed"
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

      (briefs.to_a + checks.to_a).sort_by(&:due_at).first(12).map do |record|
        if record.is_a?(Delivery)
          Row.new(
            store_name: record.org_unit.name,
            owner_name: record.assignee&.name || I18n.t("morocco.owner.unassigned"),
            due_at: record.due_at,
            tone: "late",
            status_label: record.communication.title,
            path: routes.communication_path(record.communication),
            kind: "overdue"
          )
        else
          Row.new(
            store_name: record.org_unit.name,
            owner_name: record.assignee&.name || I18n.t("morocco.owner.unassigned"),
            due_at: record.due_at,
            tone: "late",
            status_label: record.checklist.title,
            path: routes.checklist_path(record.checklist),
            kind: "overdue"
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
          path: Rails.application.routes.url_helpers.communication_path(delivery.communication),
          kind: "redo"
        )
      end
    end
  end
end
