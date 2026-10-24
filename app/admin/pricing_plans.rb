# frozen_string_literal: true

# Confidential pricing. Super Admin only; every action is checked server-side.
ActiveAdmin.register PricingPlan do
  menu priority: 3, label: "Pricing", if: proc { current_user&.super_admin? }
  actions :index, :show, :edit, :update

  permit_params :unit_price, :active_for_sales, :max_stores, :max_discount_percent, :volume_tiers

  controller do
    before_action :require_platform_admin!

    def scoped_collection
      PricingPlan.ordered
    end

    private

    def require_platform_admin!
      return if current_user&.super_admin?

      head :forbidden
    end
  end

  index do
    column(:plan) { |p| I18n.t("pricing.plans.#{p.key}.name") }
    column(:price_per_store_month) { |p| p.custom_quotation? ? "Custom" : "#{p.unit_price} #{p.currency}" }
    column :active_for_sales
    column :max_stores
    column :max_discount_percent
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row(:plan) { |p| I18n.t("pricing.plans.#{p.key}.name") }
      row :unit_price
      row :currency
      row :active_for_sales
      row :max_stores
      row :max_discount_percent
      row(:volume_tiers) { |p| p.volume_tiers.to_json }
    end
    panel "Price history" do
      table_for resource.versions.order(created_at: :desc) do
        column :created_at
        column :unit_price
        column :active_for_sales
        column(:changed_by) { |v| v.changed_by&.email || "-" }
      end
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs I18n.t("pricing.plans.#{f.object.key}.name") do
      f.input :unit_price, hint: "MAD per store per month. Blank = custom quotation. Does not change existing quotations."
      f.input :active_for_sales
      f.input :max_stores
      f.input :max_discount_percent
      f.input :volume_tiers, as: :text, input_html: { value: f.object.volume_tiers.to_json },
              hint: 'JSON, e.g. [{"min_stores":50,"discount_percent":5}]. Cannot exceed max discount.'
    end
    f.actions
  end
end
