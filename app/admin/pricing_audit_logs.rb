# frozen_string_literal: true

ActiveAdmin.register PricingAuditLog do
  menu priority: 5, label: "Pricing audit", if: proc { current_user&.super_admin? }
  actions :index, :show

  controller do
    before_action { head :forbidden unless current_user&.super_admin? }

    def scoped_collection
      PricingAuditLog.order(created_at: :desc)
    end
  end

  index do
    column :created_at
    column(:user) { |l| l.user&.email || "-" }
    column :action
    column :subject_type
    column :subject_id
    column(:changes) { |l| l.changes_made.to_json }
  end
  filter :subject_type
  filter :action
  filter :created_at
end
