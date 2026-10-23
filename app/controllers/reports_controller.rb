class ReportsController < ApplicationController
  include SpreadsheetExports
  before_action -> { require_hq_or_area(:reports) }
  before_action -> { require_feature!(:reports) }

  def show
    @date_range = Reports::DateRange.new(from: params[:from], to: params[:to])
    store_ids = if !hq_user?
      current_user.permitted_store_ids(:reports)
    end
    @report = Reports::Snapshot.new(tenant_scope, date_range: @date_range, store_ids: store_ids)
    @trends = Reports::ComplianceTrends.new(tenant_scope, date_range: @date_range, store_ids: store_ids,
      interval: params[:interval], group_by: params[:group_by])
    if spreadsheet_request?
      table = Reports::ExportTable.snapshot(@report, query: params[:query], state: params[:state])
      send_spreadsheet(table, source: "reports", filters: export_date_filters.merge(
        query: params[:query].to_s.first(200), state: params[:state].to_s.first(20),
        interval: @trends.interval, group_by: @trends.group_by))
    end
  end
end
