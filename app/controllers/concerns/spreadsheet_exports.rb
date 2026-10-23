module SpreadsheetExports
  extend ActiveSupport::Concern

  private

  def spreadsheet_request?
    request.format.csv? || request.format.xlsx?
  end

  def send_spreadsheet(table, source:, filters: {})
    format = request.format.xlsx? ? "xlsx" : "csv"
    spreadsheet = Reports::Spreadsheet.new(headers: table.headers, rows: table.rows)
    data = format == "xlsx" ? spreadsheet.xlsx : spreadsheet.csv
    record_export(source: source, format: format, row_count: table.rows.size, filters: filters)
    response.headers["Cache-Control"] = "no-store"
    send_data data, filename: "#{source}-#{tenant_scope.slug}-#{Date.current}.#{format}",
      type: format == "xlsx" ? Reports::Spreadsheet::XLSX_TYPE : "text/csv; charset=utf-8"
  end

  def record_export(source:, format:, row_count:, filters: {})
    ExportLog.create!(tenant: tenant_scope, actor: current_user, source: source, output_format: format,
      row_count: row_count, filters: filters.merge(locale: I18n.locale.to_s))
  end

  def export_date_filters
    { from: @date_range.from.iso8601, to: @date_range.to.iso8601 }
  end
end
