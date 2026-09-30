module ApplicationHelper
  BRAND_ASSET_FILES = {
    logo: "%{slug}-logo.svg",
    logo_mark: "%{slug}-mark.svg",
    favicon: "%{slug}-favicon.svg"
  }.freeze

  def localized_badge(key)
    content_tag(:span, t("common.#{key}"), class: "badge badge--#{key}")
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

    filename = BRAND_ASSET_FILES[kind]&. % { slug: tenant.slug }
    return unless filename

    public_file = Rails.root.join("public/brand", filename)
    "/brand/#{filename}" if public_file.exist?
  end
end
