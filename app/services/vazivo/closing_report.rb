module Vazivo
  # End-of-campaign summary for HQ: metrics, top/bottom stores, printable HTML.
  # Closed = sent playbook checklist with no pending stores, or past campaign day.
  class ClosingReport
    StoreRow = Struct.new(
      :store_name, :owner_name, :finished, :on_time, :overdue,
      :steps_done, :steps_total, :step_percent, :tone, :path, :rank_score,
      keyword_init: true
    )
    Summary = Struct.new(
      :checklist, :playbook, :title, :starts_on, :campaign_on, :closed,
      :total, :done, :pending, :percent, :on_time, :late, :overdue,
      :top_stores, :bottom_stores, :stores, :path, :export_path,
      keyword_init: true
    )
    Snapshot = Struct.new(:reports, :total, keyword_init: true)

    TOP_N = 5

    def self.for(tenant, checklist:)
      new(tenant).report_for(checklist)
    end

    def self.closed_for(tenant)
      new(tenant).closed_snapshot
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def closed_snapshot
      reports = closed_checklists.map { |checklist| report_for(checklist) }
      Snapshot.new(reports: reports, total: reports.size)
    end

    def report_for(checklist)
      raise ArgumentError, "checklist must belong to tenant" unless checklist.tenant_id == @tenant.id
      raise ArgumentError, "not a playbook campaign" if checklist.playbook_id.blank?

      deliveries = checklist.checklist_deliveries.to_a
      steps_total = checklist.checklist_items.size
      stores = deliveries.map { |delivery| store_row(checklist, delivery, steps_total) }
      ranked = stores.sort_by { |row| [ -row.rank_score, row.store_name ] }
      done = stores.count(&:finished)
      pending = stores.size - done
      on_time = stores.count { |row| row.finished && row.on_time }
      late = stores.count(&:overdue)
      overdue_finish = stores.count { |row| row.finished && !row.on_time }

      Summary.new(
        checklist: checklist,
        playbook: checklist.playbook,
        title: checklist.playbook&.title || checklist.title,
        starts_on: checklist.starts_on,
        campaign_on: checklist.campaign_on,
        closed: closed?(checklist, deliveries),
        total: stores.size,
        done: done,
        pending: pending,
        percent: percent_of(done, stores.size),
        on_time: on_time,
        late: late,
        overdue: overdue_finish,
        top_stores: ranked.first(TOP_N),
        bottom_stores: ranked.reverse.first(TOP_N),
        stores: ranked,
        path: routes.closing_report_playbooks_path(checklist),
        export_path: routes.closing_report_playbooks_path(checklist, export: 1)
      )
    end

    private

    def routes
      Rails.application.routes.url_helpers
    end

    def closed_checklists
      sent_campaigns.select { |checklist| closed?(checklist, checklist.checklist_deliveries.to_a) }
                    .sort_by { |checklist| [ checklist.campaign_on || Date.new(9999), checklist.id ] }
                    .reverse
    end

    def sent_campaigns
      @tenant.checklists.sent
             .where.not(playbook_id: nil)
             .includes(:playbook, :checklist_items, checklist_deliveries: [ :org_unit, :assignee, :checklist_item_responses ])
             .order(Arel.sql("checklists.campaign_on DESC NULLS LAST"), id: :desc)
    end

    def closed?(checklist, deliveries)
      return true if deliveries.any? && deliveries.none?(&:pending?)
      return true if checklist.campaign_on.present? && checklist.campaign_on < Date.current

      false
    end

    def store_row(checklist, delivery, steps_total)
      steps_done = delivery.checklist_item_responses.count(&:completed?)
      finished = delivery.finished?
      on_time = finished && (delivery.due_at.blank? || (delivery.completed_at && delivery.completed_at <= delivery.due_at))
      step_percent = percent_of(steps_done, steps_total)
      # Prefer finished + on-time, then step progress; unfinished late ranks lowest.
      rank_score = (finished ? 10_000 : 0) + (on_time ? 1_000 : 0) + step_percent - (delivery.late? ? 500 : 0)

      StoreRow.new(
        store_name: delivery.org_unit.name,
        owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
        finished: finished,
        on_time: on_time,
        overdue: delivery.late?,
        steps_done: steps_done,
        steps_total: steps_total,
        step_percent: step_percent,
        tone: delivery.tone,
        path: routes.checklist_path(checklist, anchor: "store-#{delivery.org_unit_id}"),
        rank_score: rank_score
      )
    end

    def percent_of(done, total)
      return 0 if total.zero?

      ((done.to_f / total) * 100).round
    end
  end
end
