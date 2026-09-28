# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { "HQ · #{acting_tenant.name}" } do
    tenant = acting_tenant

    if current_user.super_admin?
      panel "Platform" do
        para do
          text_node "Manage product capabilities per brand: "
          text_node link_to("Feature flags", admin_feature_flags_path)
          text_node " · "
          text_node link_to("Demo requests", admin_demo_requests_path)
          text_node " · "
          text_node link_to("Brands", admin_tenants_path)
        end
      end
    end

    columns do
      column do
        panel "Overview" do
          ul do
            li "#{tenant.org_units.stores.count} stores"
            li "#{tenant.org_units.regions.count} regions"
            li "#{tenant.users.count} users"
            li "#{tenant.communications.sent.count} briefs sent"
            li "#{tenant.checklists.sent.count} checklists sent"
          end
        end
      end

      column do
        panel "Recent briefs" do
          ul do
            tenant.communications.order(created_at: :desc).limit(5).each do |c|
              li link_to(c.title_fr, admin_communication_path(c))
            end
          end
        end
      end

      column do
        panel "Recent checklists" do
          ul do
            tenant.checklists.order(created_at: :desc).limit(5).each do |c|
              li link_to(c.title_fr, admin_checklist_path(c))
            end
          end
        end
      end
    end
  end
end
