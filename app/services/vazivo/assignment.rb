module Vazivo
  class Assignment
    StorePreview = Struct.new(:id, :name, :store_format, :cluster, keyword_init: true)

    def self.stamp!(record, due_at:)
      store = record.org_unit
      manager = store.memberships.find_by(role: "store")&.user
      attrs = {}
      attrs[:assignee] = manager if record.assignee_id.blank? && manager
      attrs[:due_at] = due_at if record.due_at.blank? && due_at.present?
      record.update!(attrs) if attrs.any?
      record
    end

    # Resolve target stores inside a tenant. Org units expand to descendant
    # stores, then optional role / format / cluster filters narrow the set.
    def self.resolve_store_ids(tenant, org_unit_ids: [], role: nil, store_format: nil, cluster: nil)
      ids = Array(org_unit_ids).compact_blank.map(&:to_i).uniq
      return [] if ids.empty?

      units = tenant.org_units.where(id: ids)
      store_ids = units.flat_map { |unit| unit.descendant_stores.pluck(:id) }.uniq
      return [] if store_ids.empty?

      stores = tenant.org_units.stores.where(id: store_ids)
      stores = stores.where(store_format: store_format) if store_format.present?
      stores = stores.where(cluster_key: cluster) if cluster.present?

      if role.present?
        stores = stores.joins(:memberships).where(memberships: { role: role }).distinct
      end

      stores.pluck(:id)
    end

    # Dry-run list of stores that would receive an assignment for the filters.
    def self.preview(tenant, org_unit_ids: [], role: nil, store_format: nil, cluster: nil)
      ids = resolve_store_ids(
        tenant,
        org_unit_ids: org_unit_ids,
        role: role,
        store_format: store_format,
        cluster: cluster
      )
      tenant.org_units.stores.where(id: ids).order(:name).map do |store|
        StorePreview.new(
          id: store.id,
          name: store.name,
          store_format: store.store_format,
          cluster: store.cluster_key
        )
      end
    end

    # Open deliveries that were sent before owner/deadline stamping still need
    # a store manager and an end-of-day clock so the today board can work.
    def self.backfill!(tenant)
      due = Schedule.default_due(tenant, nil)

      Delivery.joins(:communication)
              .includes(:org_unit, org_unit: :memberships)
              .where(communications: { tenant_id: tenant.id, status: "sent" })
              .where.not(status: %w[completed read])
              .find_each { |delivery| stamp!(delivery, due_at: due) }

      ChecklistDelivery.joins(:checklist)
                       .includes(:org_unit, org_unit: :memberships)
                       .where(checklists: { tenant_id: tenant.id, status: "sent" })
                       .where.not(status: "completed")
                       .find_each { |delivery| stamp!(delivery, due_at: due) }

      reset_false_chases!(tenant)
    end

    # Clears chase markers that were set when age without a deadline counted as late.
    def self.reset_false_chases!(tenant)
      Delivery.joins(:communication)
              .where(communications: { tenant_id: tenant.id, status: "sent" })
              .where.not(status: %w[completed read])
              .where("escalation_level > 0")
              .find_each do |delivery|
        next if delivery.due_at.present? && delivery.due_at <= 24.hours.ago

        delivery.escalation_events.delete_all
        delivery.update!(escalation_level: 0, escalated_at: nil)
      end

      ChecklistDelivery.joins(:checklist)
                       .where(checklists: { tenant_id: tenant.id, status: "sent" })
                       .where.not(status: "completed")
                       .where("escalation_level > 0")
                       .find_each do |delivery|
        next if delivery.due_at.present? && delivery.due_at <= 24.hours.ago

        delivery.escalation_events.delete_all
        delivery.update!(escalation_level: 0, escalated_at: nil)
      end
    end

    def self.backfill_all!
      Tenant.find_each { |tenant| backfill!(tenant) }
    end
  end
end
