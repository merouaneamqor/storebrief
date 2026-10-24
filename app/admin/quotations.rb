# frozen_string_literal: true

# Customer quotations. Super Admin only; drafts are never visible elsewhere.
ActiveAdmin.register Quotation do
  menu priority: 4, label: "Quotations", if: proc { current_user&.super_admin? }
  actions :index, :show, :new, :create, :edit, :update

  permit_params :pricing_plan_id, :customer_name, :customer_email, :store_count,
                :unit_price, :discount_percent, :terms, :valid_until

  member_action :issue, method: :post do
    resource.issue!
    redirect_to resource_path, notice: "Quotation issued (not sent automatically)."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to resource_path, alert: e.message
  end

  member_action :void, method: :post do
    resource.void!
    redirect_to resource_path, notice: "Quotation voided."
  end

  action_item :issue, only: :show, if: proc { resource.status == "draft" } do
    link_to "Issue", issue_admin_quotation_path(resource), method: :post
  end
  action_item :void, only: :show, if: proc { resource.status != "void" } do
    link_to "Void", void_admin_quotation_path(resource), method: :post
  end

  controller do
    before_action :require_platform_admin!

    def create
      build_resource.created_by = current_user
      super
    end

    def edit
      return redirect_to(resource_path, alert: "Issued quotations are locked.") if resource.status != "draft"

      super
    end

    private

    def require_platform_admin!
      return if current_user&.super_admin?

      head :forbidden
    end
  end

  index do
    column :reference
    column :customer_name
    column(:plan) { |q| I18n.t("pricing.plans.#{q.pricing_plan.key}.name") }
    column :store_count
    column(:monthly_total) { |q| "#{q.monthly_total} #{q.currency}" }
    column :status
    column :valid_until
    actions
  end

  show do
    attributes_table do
      row :reference
      row :status
      row :customer_name
      row :customer_email
      row(:plan) { |q| I18n.t("pricing.plans.#{q.pricing_plan.key}.name") }
      row :store_count
      row :unit_price
      row :discount_percent
      row(:monthly_total) { |q| "#{q.monthly_total} #{q.currency}" }
      row(:annual_total) { |q| "#{q.annual_total} #{q.currency}" }
      row :valid_until
      row :terms
      row :issued_at
      row :created_by
    end
  end

  form do |f|
    f.semantic_errors
    f.inputs do
      f.input :pricing_plan, collection: PricingPlan.ordered.map { |p| [ I18n.t("pricing.plans.#{p.key}.name"), p.id ] }
      f.input :customer_name
      f.input :customer_email
      f.input :store_count
      f.input :unit_price, hint: "Blank = plan default (snapshot). Required for Grand compte."
      f.input :discount_percent, hint: "Capped by the plan's approved maximum."
      f.input :valid_until, as: :datepicker
      f.input :terms
    end
    f.actions
  end
end
