module ReportsHelper
  def report_insight_text(insight)
    case insight[:key]
    when "insight_stale"
      t("reports.insight_stale", count: insight[:count], store: insight[:store])
    when "insight_watch"
      t("reports.insight_watch", behind: insight[:behind], store: insight[:store], count: insight[:count], when: time_ago_in_words(insight[:when]))
    else
      t("reports.#{insight[:key]}")
    end
  end
end
