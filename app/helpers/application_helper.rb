module ApplicationHelper
  def localized_badge(key)
    content_tag(:span, t("common.#{key}"), class: "badge badge--#{key}")
  end

  def bilingual_label(record, field)
    record.public_send(field)
  end
end
