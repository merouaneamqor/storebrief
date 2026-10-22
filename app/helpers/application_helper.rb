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

  def delivery_event_detail(event)
    payload = event.payload || {}
    case event.kind
    when "proof"
      if payload["files"].to_i.positive?
        return t("task_proof.file_count", count: payload["files"].to_i)
      end
      t(
        "morocco.history.proof_detail",
        before: payload["photo_before"] || payload[:photo_before] ? t("morocco.history.attached") : t("morocco.history.missing"),
        after: payload["photo_after"] || payload[:photo_after] ? t("morocco.history.attached") : t("morocco.history.missing")
      )
    when "verdict"
      to = payload["to"] || payload[:to]
      note = payload["note"] || payload[:note]
      [ to.present? ? t("morocco.verdict.#{to}", default: to.to_s) : "-", note.presence ].compact.join(" · ")
    when "approval_submitted"
      t("morocco.approval.waiting_title")
    when "approval_approved", "approval_rejected"
      verdict = payload["verdict"] || payload[:verdict]
      note = payload["note"] || payload[:note]
      [ verdict.present? ? t("morocco.verdict.#{verdict}", default: verdict.to_s) : "-", note.presence ].compact.join(" · ")
    when "dependency_cleared"
      t("morocco.dependency.cleared_event")
    when "comment"
      payload["body_preview"] || payload[:body_preview] || "-"
    else
      from = payload["from"] || payload[:from] || "-"
      to = payload["to"] || payload[:to] || "-"
      t("morocco.history.from_to", from: from, to: to)
    end
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

  def checklist_evidence_tag(response, css_class: "thumb")
    return unless response&.evidence_attached?

    if response.evidence_video?
      tag.video(
        src: url_for(response.photo),
        class: "#{css_class} thumb--video",
        controls: true,
        preload: "metadata"
      )
    else
      image_tag(response.photo, class: css_class, alt: "")
    end
  end
end
