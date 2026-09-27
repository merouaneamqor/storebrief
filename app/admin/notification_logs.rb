# frozen_string_literal: true

ActiveAdmin.register NotificationLog do
  menu priority: 8, label: "Notification logs"
  actions :index, :show

  controller do
    def scoped_collection
      super.where(tenant_id: current_user.tenant_id)
    end
  end

  index do
    id_column
    column :channel
    column :phone
    column :status
    column :notifiable_type
    column :user
    column :created_at
    actions
  end

  filter :channel
  filter :status
  filter :notifiable_type
  filter :created_at

  show do
    attributes_table do
      row :id
      row :channel
      row :phone
      row :status
      row :message
      row :notifiable
      row :user
      row :created_at
    end
  end
end
