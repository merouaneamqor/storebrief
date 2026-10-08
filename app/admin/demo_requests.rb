# frozen_string_literal: true

ActiveAdmin.register DemoRequest do
  menu priority: 1, label: "Demo requests", if: proc { current_user.super_admin? }

  actions :index, :show

  controller do
    before_action :require_platform_admin!

    def scoped_collection
      DemoRequest.all
    end

    private

    def require_platform_admin!
      return if current_user.super_admin?

      redirect_to admin_root_path, alert: I18n.t("auth.super_admin_required")
    end
  end

  index do
    selectable_column
    id_column
    column :company
    column :name
    column :email
    column :phone
    column :store_count
    column :preferred_locale
    column :status
    column :created_at
    actions
  end

  filter :status, as: :select, collection: DemoRequest::STATUSES
  filter :preferred_locale, as: :select, collection: DemoRequest::LOCALES
  filter :company
  filter :email
  filter :created_at

  show do
    attributes_table do
      row :id
      row :name
      row :company
      row :email
      row :phone
      row :store_count
      row :preferred_locale
      row :status
      row :created_at
      row :updated_at
    end
  end
end
