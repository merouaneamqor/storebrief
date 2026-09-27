class ReportsController < ApplicationController
  before_action :require_hq

  def show
    tenant = tenant_scope
    stores = tenant.org_units.stores.order(:name)

    brief_pending = Delivery.joins(:communication)
                            .where(communications: { tenant_id: tenant.id, status: "sent" }, status: "pending")
                            .group(:org_unit_id)
                            .count
    checklist_pending = ChecklistDelivery.joins(:checklist)
                                         .where(checklists: { tenant_id: tenant.id, status: "sent" }, status: "pending")
                                         .group(:org_unit_id)
                                         .count

    @store_rows = stores.map do |store|
      briefs = brief_pending[store.id].to_i
      checks = checklist_pending[store.id].to_i
      { store: store, briefs: briefs, checks: checks, pending: briefs + checks }
    end.sort_by { |row| [ -row[:pending], row[:store].name ] }

    sent_briefs = Delivery.joins(:communication).where(communications: { tenant_id: tenant.id, status: "sent" })
    sent_checks = ChecklistDelivery.joins(:checklist).where(checklists: { tenant_id: tenant.id, status: "sent" })
    brief_total = sent_briefs.count
    brief_done = sent_briefs.where(status: %w[completed read]).count
    check_total = sent_checks.count
    check_done = sent_checks.where(status: "completed").count

    @summary = {
      stores: stores.size,
      behind: @store_rows.count { |row| row[:pending].positive? },
      clear: @store_rows.count { |row| row[:pending].zero? },
      brief_percent: percent(brief_done, brief_total),
      checklist_percent: percent(check_done, check_total),
      open_briefs: brief_total - brief_done,
      open_checklists: check_total - check_done
    }

    @open_briefs = Delivery.joins(:communication)
                           .includes(:org_unit, :communication)
                           .where(communications: { tenant_id: tenant.id, status: "sent" }, status: "pending")
                           .order(:created_at)
                           .limit(15)
    @open_checklists = ChecklistDelivery.joins(:checklist)
                                        .includes(:org_unit, :checklist)
                                        .where(checklists: { tenant_id: tenant.id, status: "sent" }, status: "pending")
                                        .order(:created_at)
                                        .limit(15)
  end

  private

  def percent(done, total)
    return 0 if total.zero?

    ((done.to_f / total) * 100).round
  end
end
