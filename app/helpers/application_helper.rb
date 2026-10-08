module ApplicationHelper
  BRAND_ASSET_FILES = {
    logo: "%{slug}-logo.svg",
    logo_mark: "%{slug}-mark.svg",
    favicon: "%{slug}-favicon.svg"
  }.freeze

  def localized_badge(key)
    content_tag(:span, t("common.#{key}"), class: "badge badge--#{key}")
  end

  # Routine is the quiet default, so only urgent and important tasks get a badge.
  def priority_badge(priority)
    return if priority.blank? || priority == Communication::DEFAULT_PRIORITY

    content_tag(:span, t("common.priorities.#{priority}"), class: "badge badge--priority-#{priority}")
  end

  # One line description of a recurrence rule, e.g. "Every week on Mon, Wed".
  def recurrence_summary(rule)
    return "-" if rule.blank?

    base = case rule["frequency"]
    when "weekly"
      names = t("communications.recurrence.weekdays")
      t("communications.recurrence.summary.weekly", days: Array(rule["weekdays"]).map { |wday| names[wday.to_i] }.join(", "))
    when "custom"
      t("communications.recurrence.summary.custom", count: rule["interval"].to_i)
    else
      t("communications.recurrence.summary.daily")
    end
    return base if rule["ends_on"].blank?

    "#{base} · #{t('communications.recurrence.summary.until', date: rule['ends_on'])}"
  end

  def bilingual_label(record, field)
    record.public_send(field)
  end

  # Prefer a live Active Storage blob; fall back to seed SVGs in public/brand/
  # when the blob points at missing ephemeral disk files (common on Render).
  def tenant_brand_asset_src(tenant, kind)
    return if tenant.blank?

    kind = kind.to_sym
    attachment = tenant.public_send(kind) if tenant.respond_to?(kind)
    if attachment&.attached?
      begin
        return url_for(attachment) if attachment.blob.service.exist?(attachment.blob.key)
      rescue StandardError
        # Fall through to the packaged seed asset.
      end
    end

    template = BRAND_ASSET_FILES[kind]
    return unless template

    filename = format(template, slug: tenant.slug)
    public_file = Rails.root.join("public/brand", filename)
    "/brand/#{filename}" if public_file.exist?
  end
end
