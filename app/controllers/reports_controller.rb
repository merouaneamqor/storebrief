class ReportsController < ApplicationController
  before_action -> { require_hq_or_area(:reports) }
  before_action -> { require_feature!(:reports) }

  def show
    @date_range = Reports::DateRange.new(from: params[:from], to: params[:to])
    store_ids = if !hq_user?
      current_user.memberships.where(role: "area").includes(:org_unit).flat_map { |membership| membership.org_unit.descendant_stores.ids }.uniq
    end
    @report = Reports::Snapshot.new(tenant_scope, date_range: @date_range, store_ids: store_ids)
    @trends = Reports::ComplianceTrends.new(tenant_scope, date_range: @date_range, store_ids: store_ids,
      interval: params[:interval], group_by: params[:group_by])
  end
end
