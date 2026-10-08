# frozen_string_literal: true

ActiveAdmin.register OrgUnit do
  menu priority: 2, label: "Org units"

  permit_params :name, :unit_type, :parent_id

  controller do
    def scoped_collection
      super.where(tenant_id: acting_tenant.id)
    end

    def build_new_resource
      super.tap { |r| r.tenant = acting_tenant }
    end
  end

  index do
    selectable_column
    id_column
    column :name
    column :unit_type
    column :parent
    column :created_at
    actions
  end

  filter :name
  filter :unit_type, as: :select, collection: OrgUnit::UNIT_TYPES
  filter :parent

  form do |f|
    f.inputs do
      f.input :name
      f.input :unit_type, as: :select, collection: OrgUnit::UNIT_TYPES
      f.input :parent,
              as: :select,
              collection: acting_tenant.org_units.where.not(unit_type: "store").order(:name),
              include_blank: true
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :unit_type
      row :parent
      row :created_at
      row :updated_at
    end
  end
end
