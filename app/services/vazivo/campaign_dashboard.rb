module Vazivo
  # HQ view of live playbook campaigns: one row per deployed playbook (checklist),
  # with store completion/compliance and the stores that need a push.
  class CampaignDashboard
    StoreRow = Struct.new(:store_name, :owner_name, :due_at, :tone, :steps_done, :steps_total, :path, keyword_init: true)
    Campaign = Struct.new(
      :checklist, :playbook, :campaign_on, :total, :done, :percent, :exceptions, :path,
      keyword_init: true
    ) do
      def pending = total - done
      def title = playbook&.title || checklist.title
    end
    Snapshot = Struct.new(:campaigns, :total, :done, :percent, :exception_count, keyword_init: true)

    def self.for(tenant)
      new(tenant).snapshot
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def snapshot
      campaigns = live_checklists.map { |checklist| build_campaign(checklist) }
      total = campaigns.sum(&:total)
      done = campaigns.sum(&:done)
      Snapshot.new(
        campaigns: campaigns,
        total: total,
        done: done,
        percent: percent_of(done, total),
        exception_count: campaigns.sum { |campaign| campaign.exceptions.size }
      )
    end

    private

    def routes
      Rails.application.routes.url_helpers
    end

    # Sent playbook deploys that still have at least one store to finish.
    def live_checklists
      @tenant.checklists.sent
             .where.not(playbook_id: nil)
             .where(id: ChecklistDelivery.pending.select(:checklist_id))
             .includes(:playbook, :checklist_items, checklist_deliveries: [ :org_unit, :assignee, :checklist_item_responses ])
             .order(Arel.sql("checklists.campaign_on ASC NULLS LAST"), :id)
    end

    def build_campaign(checklist)
      deliveries = checklist.checklist_deliveries.to_a
      done = deliveries.count(&:completed?)
      Campaign.new(
        checklist: checklist,
        playbook: checklist.playbook,
        campaign_on: checklist.campaign_on,
        total: deliveries.size,
        done: done,
        percent: percent_of(done, deliveries.size),
        exceptions: exception_rows(checklist, deliveries),
        path: routes.checklist_path(checklist)
      )
    end

    def exception_rows(checklist, deliveries)
      steps_total = checklist.checklist_items.size
      deliveries.select(&:late?).sort_by(&:due_at).map do |delivery|
        StoreRow.new(
          store_name: delivery.org_unit.name,
          owner_name: delivery.assignee&.name || I18n.t("morocco.owner.unassigned"),
          due_at: delivery.due_at,
          tone: delivery.tone,
          steps_done: delivery.checklist_item_responses.count(&:completed?),
          steps_total: steps_total,
          path: routes.checklist_path(checklist, anchor: "store-#{delivery.org_unit_id}")
        )
      end
    end

    def percent_of(done, total)
      return 0 if total.zero?

      ((done.to_f / total) * 100).round
    end
  end
end
