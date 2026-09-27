# frozen_string_literal: true

ActiveAdmin.register Membership do
  menu priority: 4, label: "Memberships"

  permit_params :user_id, :org_unit_id, :role

  controller do
    def scoped_collection
      super.joins(:user).where(users: { tenant_id: current_user.tenant_id })
    end
  end

  index do
    selectable_column
    id_column
    column :user
    column :org_unit
    column :role
    column :created_at
    actions
  end

  filter :role, as: :select, collection: Membership::ROLES
  filter :user
  filter :org_unit

  form do |f|
    f.inputs do
      f.input :user, as: :select, collection: current_user.tenant.users.order(:name)
      f.input :org_unit, as: :select, collection: current_user.tenant.org_units.order(:name)
      f.input :role, as: :select, collection: Membership::ROLES
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :user
      row :org_unit
      row :role
      row :created_at
      row :updated_at
    end
  end
end
