class RankingsController < ApplicationController
  include SpreadsheetExports
  before_action -> { require_feature!(:morocco_ops) }

  def show
    @date_range = Reports::DateRange.new(from: params[:from], to: params[:to],
      default_from: Vazivo::Schedule.now.beginning_of_week.to_date,
      default_to: Vazivo::Schedule.now.end_of_week.to_date)
    store_ids = unless hq_user?
      current_user.permitted_store_ids(store_user? ? :inbox : :reports)
    end
    @ranking = Vazivo::Ranking.for(tenant_scope, date_range: @date_range, store_ids: store_ids)
    send_spreadsheet(Reports::ExportTable.ranking(@ranking), source: "ranking", filters: export_date_filters) if spreadsheet_request?
  end
end
