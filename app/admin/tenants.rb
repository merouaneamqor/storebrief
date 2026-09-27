# frozen_string_literal: true

# HQ can edit their own brand only — no create/destroy (no new tenants).
ActiveAdmin.register Tenant do
  menu priority: 9, label: "Brand"
  actions :show, :edit, :update

  permit_params(
    :brand_name, :tagline,
    :logo, :logo_mark, :favicon,
    :remove_logo, :remove_logo_mark, :remove_favicon,
    *Tenant::BRAND_COLORS.keys
  )

  controller do
    def scoped_collection
      super.where(id: current_user.tenant_id)
    end

    def find_resource
      current_user.tenant
    end

    def index
      redirect_to admin_tenant_path(current_user.tenant)
    end
  end

  form html: { multipart: true } do |f|
    f.semantic_errors
    f.inputs "Identity" do
      f.input :name, input_html: { disabled: true }
      f.input :slug, input_html: { disabled: true }
      f.input :brand_name, hint: "Shown in the app sidebar and browser title"
      f.input :tagline, hint: "Optional short line under the brand name"
    end

    f.inputs "Logo & icons" do
      fields = Tenant::BRAND_ASSETS.map do |attr, meta|
        attachment = f.object.public_send(attr)
        preview = if attachment.attached?
          url = helpers.url_for(attachment)
          <<~PREVIEW
            <div style="margin:8px 0;display:flex;align-items:center;gap:12px;flex-wrap:wrap">
              <img src="#{url}" alt="#{meta[:label]}" style="max-height:48px;max-width:160px;background:#111;padding:6px;border-radius:6px">
              <span>#{ERB::Util.html_escape(attachment.filename.to_s)}</span>
              <label style="display:inline-flex;align-items:center;gap:6px;font-weight:500">
                <input type="checkbox" name="tenant[remove_#{attr}]" value="1" id="tenant_remove_#{attr}">
                Remove
              </label>
            </div>
          PREVIEW
        else
          ""
        end

        <<~FIELD
          <li class="brand-asset-field">
            <label for="tenant_#{attr}" class="label">#{meta[:label]}</label>
            #{preview}
            <input type="file"
                   name="tenant[#{attr}]"
                   id="tenant_#{attr}"
                   accept="image/png,image/jpeg,image/webp,image/svg+xml,image/x-icon,.ico">
            <p class="inline-hints">#{meta[:hint]}</p>
          </li>
        FIELD
      end
      text_node fields.join.html_safe
    end

    Tenant::BRAND_COLORS.group_by { |_, meta| meta[:group] }.each do |group, attrs|
      f.inputs group do
        fields = attrs.map do |attr, meta|
          value = f.object.public_send(attr).presence || meta[:default]
          <<~FIELD
            <li class="brand-color-field">
              <label for="tenant_#{attr}" class="label">#{meta[:label]}</label>
              <div style="display:flex;align-items:center;gap:14px;margin-top:8px;flex-wrap:wrap">
                <input type="color"
                       class="brand-swatch"
                       data-target="tenant_#{attr}"
                       value="#{value}"
                       aria-label="#{meta[:label]}"
                       style="width:3.5rem;height:2.5rem;padding:0;border:1px solid #c9c9c9;border-radius:8px;cursor:pointer;background:transparent">
                <input type="text"
                       name="tenant[#{attr}]"
                       id="tenant_#{attr}"
                       class="brand-hex"
                       value="#{value}"
                       pattern="#[0-9A-Fa-f]{6}"
                       maxlength="7"
                       required
                       autocomplete="off"
                       style="width:8rem;font-family:ui-monospace,monospace;font-size:14px;padding:8px 10px;border:1px solid #c9c9c9;border-radius:6px">
                <span class="brand-preview"
                      data-for="tenant_#{attr}"
                      style="display:inline-block;width:1.75rem;height:1.75rem;border-radius:6px;border:1px solid #ccc;background:#{value}"></span>
                <code style="color:#666;font-size:12px">#{meta[:css]}</code>
              </div>
            </li>
          FIELD
        end
        text_node fields.join.html_safe
      end
    end

    f.actions

    text_node <<~HTML.html_safe
      <script>
        (function () {
          function syncPreview(id, value) {
            var preview = document.querySelector('.brand-preview[data-for="' + id + '"]');
            if (preview && /^#[0-9A-Fa-f]{6}$/.test(value)) preview.style.background = value;
          }

          document.querySelectorAll(".brand-swatch").forEach(function (swatch) {
            swatch.addEventListener("input", function () {
              var text = document.getElementById(swatch.dataset.target);
              if (!text) return;
              text.value = swatch.value;
              syncPreview(text.id, swatch.value);
            });
          });

          document.querySelectorAll(".brand-hex").forEach(function (text) {
            text.addEventListener("input", function () {
              var value = text.value.trim();
              if (!value.startsWith("#")) value = "#" + value;
              text.value = value;
              if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return;
              var swatch = document.querySelector('.brand-swatch[data-target="' + text.id + '"]');
              if (swatch) swatch.value = value.toLowerCase();
              syncPreview(text.id, value);
            });
          });
        })();
      </script>
    HTML
  end

  show title: proc { |t| "#{t.display_brand_name} brand" } do
    attributes_table do
      row :name
      row :slug
      row :brand_name
      row :tagline
    end

    panel "Logo & icons" do
      attributes_table_for resource do
        Tenant::BRAND_ASSETS.each do |attr, meta|
          row meta[:label] do |t|
            file = t.public_send(attr)
            if file.attached?
              div do
                text_node %(<div style="display:flex;align-items:center;gap:12px"><img src="#{helpers.url_for(file)}" alt="#{meta[:label]}" style="max-height:48px;max-width:160px;background:#111;padding:6px;border-radius:6px"><span>#{ERB::Util.html_escape(file.filename.to_s)}</span></div>).html_safe
              end
            else
              status_tag "not set"
            end
          end
        end
      end
    end

    Tenant::BRAND_COLORS.group_by { |_, meta| meta[:group] }.each do |group, attrs|
      panel group do
        attributes_table_for resource do
          attrs.each do |attr, meta|
            row meta[:label] do |t|
              value = t.public_send(attr)
              div style: "display:flex;align-items:center;gap:12px" do
                span style: "display:inline-block;width:28px;height:28px;border-radius:6px;background:#{value};border:1px solid #ccc"
                span "#{value}  (#{meta[:css]})"
              end
            end
          end
        end
      end
    end
  end
end
