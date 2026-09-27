# frozen_string_literal: true

ActiveAdmin.register User do
  menu priority: 3, label: "Users"

  permit_params :name, :email, :locale, :whatsapp_phone, :password, :password_confirmation

  controller do
    def scoped_collection
      super.where(tenant_id: current_user.tenant_id)
    end

    def build_new_resource
      super.tap { |r| r.tenant = current_user.tenant }
    end
  end

  index do
    selectable_column
    id_column
    column :name
    column :email
    column :locale
    column("HQ?") { |u| status_tag(u.hq? ? "yes" : "no") }
    column :created_at
    actions
  end

  filter :name
  filter :email
  filter :locale, as: :select, collection: User::LOCALES

  form do |f|
    f.inputs do
      f.input :name
      f.input :email
      f.input :locale, as: :select, collection: User::LOCALES
      f.input :whatsapp_phone
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :email
      row :locale
      row :whatsapp_phone
      row("HQ?") { |u| u.hq? }
      row :created_at
      row :updated_at
    end

    panel "Memberships" do
      table_for resource.memberships.includes(:org_unit) do
        column :id
        column :role
        column :org_unit
      end
    end
  end
end
