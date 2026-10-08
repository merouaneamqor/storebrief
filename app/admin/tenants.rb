# frozen_string_literal: true

# HQ can edit their own brand only — no create/destroy (no new tenants).
# Super-admins can also configure per-tenant SAML SSO.
ActiveAdmin.register Tenant do
  menu priority: 9, label: "Brand"
  actions :index, :show, :edit, :update

  permit_params do
    allowed = [
      :brand_name, :tagline,
      :logo, :logo_mark, :favicon,
      :remove_logo, :remove_logo_mark, :remove_favicon,
      *Tenant::BRAND_COLORS.keys,
      {
        mail_setting_attributes: %i[
          id use_platform from_email from_name
          smtp_address smtp_port smtp_domain smtp_username smtp_password
          smtp_authentication smtp_enable_starttls_auto
        ]
      }
    ]
    if current_user.super_admin?
      allowed.concat(Tenant::FEATURE_FLAGS.keys.map { |k| :"feature_#{k}" })
      allowed << {
        saml_setting_attributes: %i[
          id enabled sso_enforced
          idp_entity_id idp_sso_target_url idp_cert email_attribute
        ]
      }
    end
    allowed
  end

  controller do
    def scoped_collection
      return super if current_user.super_admin?

      super.where(id: acting_tenant.id)
    end

    def find_resource
      return super if current_user.super_admin?

      acting_tenant
    end

    def index
      return super if current_user.super_admin?

      redirect_to admin_tenant_path(acting_tenant)
    end

    def edit
      resource.saml_setting_or_build if current_user.super_admin?
      resource.mail_setting_or_build
      super
    end
  end

  index do
    id_column
    column :name
    column :slug
    column :brand_name
    if current_user.super_admin?
      column("SSO") { |t| status_tag(t.saml_sso_enabled? ? "on" : "off") }
      column("Flags") do |t|
        on = Tenant::FEATURE_FLAGS.keys.count { |k| t.feature?(k) }
        "#{on}/#{Tenant::FEATURE_FLAGS.size}"
      end
    end
    actions
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

    f.object.mail_setting_or_build
    f.inputs "Outbound email (SMTP)" do
      text_node <<~HTML.html_safe
        <li>
          <p class="inline-hints">
            Configure your brand SMTP to send alerts from your domain.
            If you leave <strong>Use Vazivo SMTP</strong> on, Vazivo sends on your behalf and those emails are billed.
            WhatsApp messages are billed separately when that channel is on. Push stays included.
          </p>
        </li>
      HTML
      f.semantic_fields_for :mail_setting do |mf|
        mf.input :use_platform, as: :boolean,
                 label: "Use Vazivo SMTP (billed)",
                 hint: "Turn off to use your own SMTP below"
        mf.input :from_name, hint: "Display name on emails"
        mf.input :from_email, hint: "Required when using your SMTP"
        mf.input :smtp_address, hint: "e.g. smtp.office365.com"
        mf.input :smtp_port
        mf.input :smtp_domain
        mf.input :smtp_username
        mf.input :smtp_password, as: :string,
                 input_html: { type: "password", autocomplete: "new-password", value: "" },
                 hint: "Leave blank to keep the current password"
        mf.input :smtp_authentication, as: :select, collection: TenantMailSetting::AUTH_METHODS
        mf.input :smtp_enable_starttls_auto, as: :boolean, label: "STARTTLS"
      end
    end

    if current_user.super_admin?
      f.inputs "Features" do
        para do
          text_node "Or manage all brands from "
          text_node link_to("Feature flags", admin_feature_flags_path)
          text_node "."
        end
        Tenant::FEATURE_FLAGS.each do |key, meta|
          f.input :"feature_#{key}", as: :boolean, label: meta[:label], hint: meta[:hint]
        end
      end

      f.object.saml_setting_or_build
      urls = Saml::SettingsBuilder.urls_for(f.object, request: controller.request)
      f.inputs "SSO (SAML)" do
        text_node %(<li><p class="inline-hints">Requires the <strong>SAML SSO</strong> feature flag above. IdP details only apply when that flag is on.</p></li>).html_safe
        f.semantic_fields_for :saml_setting do |sf|
          sf.input :enabled, as: :boolean, hint: "Turn on SSO for this brand once IdP fields below are set"
          sf.input :sso_enforced, as: :boolean, hint: "Hide password login for this brand (platform admins still use password on the apex host)"
          sf.input :idp_entity_id, hint: "IdP Entity ID / Issuer"
          sf.input :idp_sso_target_url, hint: "IdP HTTP-Redirect SSO URL"
          sf.input :idp_cert, as: :text, input_html: { rows: 8 },
                              hint: "IdP signing certificate (PEM or base64 body)"
          sf.input :email_attribute, hint: "Optional SAML attribute name for email (default: NameID / email / mail)"
        end
        text_node <<~HTML.html_safe
          <li class="saml-sp-urls">
            <label class="label">Service Provider URLs (register these with the IdP)</label>
            <p class="inline-hints">
              <strong>Entity ID</strong><br>
              <code>#{ERB::Util.html_escape(urls.sp_entity_id)}</code>
            </p>
            <p class="inline-hints">
              <strong>ACS (Assertion Consumer Service)</strong><br>
              <code>#{ERB::Util.html_escape(urls.acs_url)}</code>
            </p>
            <p class="inline-hints">
              <strong>Metadata</strong><br>
              <code>#{ERB::Util.html_escape(urls.metadata_url)}</code>
            </p>
          </li>
        HTML
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

    panel "Outbound email" do
      setting = resource.mail_setting_or_build
      attributes_table_for setting do
        row("Mode") do
          if setting.configured_tenant_smtp?
            status_tag "tenant SMTP"
          else
            status_tag "Vazivo SMTP (billed)"
          end
        end
        row :use_platform
        row :from_name
        row :from_email
        row :smtp_address
        row :smtp_port
        row :smtp_domain
        row :smtp_username
        row("SMTP password") { setting.smtp_password.present? ? "••••••" : status_tag("not set") }
      end
    end

    if current_user.super_admin?
      panel "Features" do
        attributes_table_for resource do
          Tenant::FEATURE_FLAGS.each do |key, meta|
            row(meta[:label]) { |t| status_tag(t.feature?(key) ? "on" : "off") }
          end
        end
      end

      panel "SSO (SAML)" do
        setting = resource.saml_setting
        urls = Saml::SettingsBuilder.urls_for(resource, request: controller.request)
        if setting
          attributes_table_for setting do
            row("Feature flag") { status_tag(resource.feature?(:saml_sso) ? "on" : "off") }
            row("Enabled") { |s| status_tag(s.enabled? ? "yes" : "no") }
            row("SSO enforced") { |s| status_tag(s.sso_enforced? ? "yes" : "no") }
            row :idp_entity_id
            row :idp_sso_target_url
            row("IdP certificate") { |s| s.idp_cert.present? ? status_tag("set") : status_tag("missing") }
            row :email_attribute
          end
        else
          para "Not configured."
        end
        attributes_table do
          row("SP Entity ID") { urls.sp_entity_id }
          row("ACS URL") { urls.acs_url }
          row("Metadata URL") { link_to urls.metadata_url, urls.metadata_url, target: "_blank", rel: "noopener" }
        end
      end
    end
  end
end
