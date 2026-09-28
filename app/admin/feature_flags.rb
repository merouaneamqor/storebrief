# frozen_string_literal: true

# Platform-admin matrix to toggle per-brand product capabilities.
ActiveAdmin.register Tenant, as: "FeatureFlag" do
  menu priority: 2, label: "Feature flags", if: proc { current_user.super_admin? }
  actions :index, :show, :edit, :update

  permit_params(*Tenant::FEATURE_FLAGS.keys.map { |k| :"feature_#{k}" })

  controller do
    before_action :require_platform_admin!

    def scoped_collection
      Tenant.order(:name)
    end

    private

    def require_platform_admin!
      return if current_user.super_admin?

      redirect_to admin_root_path, alert: I18n.t("auth.super_admin_required")
    end
  end

  filter :name
  filter :slug

  index title: "Feature flags" do
    column :name do |t|
      link_to t.name, admin_feature_flag_path(t)
    end
    column :slug
    Tenant::FEATURE_FLAGS.each do |key, meta|
      column(meta[:label]) { |t| status_tag(t.feature?(key) ? "on" : "off", class: t.feature?(key) ? "ok" : "no") }
    end
    actions defaults: false do |t|
      item "Edit", edit_admin_feature_flag_path(t)
      item "Brand", edit_admin_tenant_path(t)
    end
  end

  show title: proc { |t| "Features · #{t.name}" } do
    attributes_table title: "Brand" do
      row :name
      row :slug
      row("Brand settings") { |t| link_to "Edit brand / SSO", edit_admin_tenant_path(t) }
    end

    panel "Feature flags" do
      attributes_table_for resource do
        Tenant::FEATURE_FLAGS.each do |key, meta|
          row(meta[:label]) do |t|
            span status_tag(t.feature?(key) ? "on" : "off")
            span " — #{meta[:hint]}", style: "color:#666;margin-left:0.5rem"
          end
        end
      end
    end
  end

  form title: proc { |t| "Feature flags · #{t.name}" } do |f|
    f.semantic_errors
    f.inputs "#{f.object.name} (#{f.object.slug})" do
      Tenant::FEATURE_FLAGS.each do |key, meta|
        f.input :"feature_#{key}", as: :boolean, label: meta[:label], hint: meta[:hint]
      end
    end

    f.actions do
      f.action :submit, label: "Save feature flags"
      f.cancel_link admin_feature_flags_path
    end
  end
end
