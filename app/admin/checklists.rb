# frozen_string_literal: true

ActiveAdmin.register Checklist do
  menu priority: 7, label: "Checklists"

  permit_params :status, :title_fr, :title_ar, :description_fr, :description_ar,
                :author_id, :checklist_template_id

  controller do
    def scoped_collection
      super.where(tenant_id: acting_tenant.id)
    end

    def build_new_resource
      super.tap do |r|
        r.tenant = acting_tenant
        r.author ||= current_user
      end
    end
  end

  index do
    selectable_column
    id_column
    column :title_fr
    column :status
    column :author
    column :checklist_template
    column :created_at
    actions
  end

  filter :title_fr
  filter :status, as: :select, collection: Checklist::STATUSES
  filter :author
  filter :checklist_template

  form do |f|
    f.inputs do
      f.input :author, as: :select, collection: acting_tenant.users.order(:name)
      f.input :checklist_template,
              as: :select,
              collection: acting_tenant.checklist_templates.order(:title_fr),
              include_blank: true
      f.input :status, as: :select, collection: Checklist::STATUSES
      f.input :title_fr
      f.input :title_ar
      f.input :description_fr, as: :text
      f.input :description_ar, as: :text
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :title_fr
      row :title_ar
      row :description_fr
      row :description_ar
      row :status
      row :author
      row :checklist_template
      row :created_at
      row :updated_at
    end

    panel "Items" do
      table_for resource.checklist_items do
        column :position
        column :title_fr
        column :title_ar
        column :requires_photo
      end
    end

    panel "Deliveries" do
      table_for resource.checklist_deliveries.includes(:org_unit) do
        column :id
        column :org_unit
        column :status
        column :completed_at
      end
    end
  end
end
