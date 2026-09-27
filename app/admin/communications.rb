# frozen_string_literal: true

ActiveAdmin.register Communication do
  menu priority: 5, label: "Briefs"

  permit_params :format, :status, :title_fr, :title_ar, :body_fr, :body_ar, :author_id

  controller do
    def scoped_collection
      super.where(tenant_id: current_user.tenant_id)
    end

    def build_new_resource
      super.tap do |r|
        r.tenant = current_user.tenant
        r.author ||= current_user
      end
    end
  end

  index do
    selectable_column
    id_column
    column :title_fr
    column :format
    column :status
    column :author
    column :created_at
    actions
  end

  filter :title_fr
  filter :format, as: :select, collection: Communication::FORMATS
  filter :status, as: :select, collection: Communication::STATUSES
  filter :author

  form do |f|
    f.inputs do
      f.input :author, as: :select, collection: current_user.tenant.users.order(:name)
      f.input :format, as: :select, collection: Communication::FORMATS
      f.input :status, as: :select, collection: Communication::STATUSES
      f.input :title_fr
      f.input :title_ar
      f.input :body_fr, as: :text
      f.input :body_ar, as: :text
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :title_fr
      row :title_ar
      row :body_fr
      row :body_ar
      row :format
      row :status
      row :author
      row :created_at
      row :updated_at
    end

    panel "Deliveries" do
      table_for resource.deliveries.includes(:org_unit) do
        column :id
        column :org_unit
        column :status
        column :completed_at
      end
    end
  end
end
