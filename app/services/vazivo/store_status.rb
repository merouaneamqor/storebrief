module Vazivo
  # Today's store health in three buckets, built only from signals that already exist:
  # overdue work, redo verdicts and unconfirmed instructions (same sources as HqBoard).
  #
  #   critical: a store with overdue work or a redo verdict still open
  #   attention: not critical, but work is due within hours or the latest brief is unconfirmed
  #   on_track: everything else
  class StoreStatus
    BUCKETS = %w[on_track attention critical].freeze
    URGENT_WINDOW = 3.hours

    Result = Struct.new(:stores_by_bucket, keyword_init: true) do
      def count(bucket)
        stores_by_bucket.fetch(bucket.to_s, []).size
      end

      def counts
        BUCKETS.index_with { |bucket| count(bucket) }
      end

      def stores(bucket)
        stores_by_bucket.fetch(bucket.to_s, [])
      end

      def total
        stores_by_bucket.values.sum(&:size)
      end
    end

    def self.for(tenant)
      new(tenant).result
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def result
      critical_ids = overdue_store_ids | redo_store_ids
      attention_ids = (urgent_store_ids | unconfirmed_store_ids) - critical_ids
      grouped = stores.group_by do |store|
        if critical_ids.include?(store.id) then "critical"
        elsif attention_ids.include?(store.id) then "attention"
        else "on_track"
        end
      end
      Result.new(stores_by_bucket: BUCKETS.index_with { |bucket| grouped.fetch(bucket, []) })
    end

    private

    def stores
      @stores ||= @tenant.org_units.stores.includes(:parent).order(:name).to_a
    end

    def open_deliveries
      Delivery.joins(:communication)
              .where(communications: { tenant_id: @tenant.id, status: "sent" })
              .where.not(status: %w[completed read])
              .where.not(due_at: nil)
    end

    def open_checklist_deliveries
      ChecklistDelivery.joins(:checklist)
                       .where(checklists: { tenant_id: @tenant.id, status: "sent" })
                       .where.not(status: "completed")
                       .where.not(due_at: nil)
    end

    def overdue_store_ids
      now = Time.current
      (open_deliveries.where("deliveries.due_at < ?", now).distinct.pluck(:org_unit_id) |
        open_checklist_deliveries.where("checklist_deliveries.due_at < ?", now).distinct.pluck(:org_unit_id))
    end

    def urgent_store_ids
      window = Time.current..URGENT_WINDOW.from_now
      (open_deliveries.where(due_at: window).distinct.pluck(:org_unit_id) |
        open_checklist_deliveries.where(due_at: window).distinct.pluck(:org_unit_id))
    end

    def redo_store_ids
      Delivery.joins(:communication)
              .where(communications: { tenant_id: @tenant.id })
              .where(verdict: "non_conforme", status: "pending")
              .distinct.pluck(:org_unit_id)
    end

    def unconfirmed_store_ids
      brief = @tenant.communications.sent.order(created_at: :desc).first
      return [] unless brief

      brief.deliveries.where(awareness: "pending").pluck(:org_unit_id)
    end
  end
end
