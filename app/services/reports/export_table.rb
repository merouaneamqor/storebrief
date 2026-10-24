module Reports
  class ExportTable
    Table = Struct.new(:headers, :rows, keyword_init: true)

    def self.build(keys, rows)
      Table.new(headers: keys.map { |key| I18n.t("spreadsheet_exports.columns.#{key}") }, rows: rows)
    end

    def self.snapshot(report, query: nil, state: nil)
      query = query.to_s.strip.downcase
      rows = report.store_rows.select do |row|
        matches_query = "#{row[:store].name} #{row[:place]&.name}".downcase.include?(query)
        matches_state = !%w[behind clear].include?(state) || (state == "behind" ? row[:pending].positive? : row[:pending].zero?)
        matches_query && matches_state
      end
      build(%w[store region open_briefs open_checklists pending oldest], rows.map do |row|
        [ row[:store].name, row[:place]&.name, row[:briefs], row[:checks], row[:pending], row[:oldest_at]&.iso8601 ]
      end)
    end

    def self.ranking(ranking)
      vm = ranking.vm_rows.index_by { |row| row.store.id }
      rows = ranking.rows.map do |row|
        [ row.store.name, row.percent, row.done, row.total, row.on_time_percent, row.conforme,
          row.previous_percent, row.delta, vm[row.store.id]&.percent ]
      end
      # A store can have merchandising scores without any brief/checklist work.
      ranking.vm_rows.reject { |score| ranking.rows.any? { |row| row.store.id == score.store.id } }.each do |score|
        rows << [ score.store.name, nil, 0, 0, nil, 0, nil, nil, score.percent ]
      end
      build(%w[store percent done total on_time_percent conforme previous_percent delta vm_percent], rows)
    end

    def self.closing(report)
      build(%w[store owner done on_time overdue steps_done steps_total percent], report.stores.map do |row|
        [ row.store_name, row.owner_name, yes_no(row.finished), yes_no(row.on_time), yes_no(row.overdue),
          row.steps_done, row.steps_total, row.step_percent ]
      end)
    end

    def self.deliveries(deliveries)
      build(%w[store title status owner due_at completed_at score verdict], deliveries.map do |delivery|
        parent = delivery.is_a?(Delivery) ? delivery.communication : delivery.checklist
        [ delivery.org_unit.name, parent.title, I18n.t("common.#{delivery.status}", default: delivery.status),
          delivery.assignee&.name, delivery.due_at&.iso8601, delivery.completed_at&.iso8601,
          delivery.respond_to?(:score) ? delivery.score : nil, delivery.respond_to?(:verdict) ? delivery.verdict : nil ]
      end)
    end

    def self.yes_no(value)
      I18n.t("spreadsheet_exports.#{value ? 'yes' : 'no'}")
    end
  end
end
