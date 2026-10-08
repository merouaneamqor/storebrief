class EmailNotifier
  def self.notify_communication!(communication)
    new.notify_communication!(communication)
  end

  def self.notify_checklist!(checklist)
    new.notify_checklist!(checklist)
  end

  def notify_communication!(communication)
    tenant = communication.tenant
    return unless tenant.feature?(:email_alerts)

    setting = tenant.mail_setting_or_build
    billed = setting.delivery_mode == :platform_billed
    return if billed && !PlatformMail.configured?

    communication.deliveries.includes(org_unit: { memberships: :user }).find_each do |delivery|
      store_users_for(delivery.org_unit).each do |user|
        next if user.email.blank?

        mail = TaskMailer.with(tenant: tenant).communication_assigned(
          user: user,
          communication: communication,
          delivery: delivery
        )
        deliver!(mail, tenant: tenant, user: user, notifiable: communication, billed: billed)
      end
    end
  end

  def notify_checklist!(checklist)
    tenant = checklist.tenant
    return unless tenant.feature?(:email_alerts)

    setting = tenant.mail_setting_or_build
    billed = setting.delivery_mode == :platform_billed
    return if billed && !PlatformMail.configured?

    checklist.checklist_deliveries.includes(org_unit: { memberships: :user }).find_each do |delivery|
      store_users_for(delivery.org_unit).each do |user|
        next if user.email.blank?

        mail = TaskMailer.with(tenant: tenant).checklist_assigned(
          user: user,
          checklist: checklist,
          delivery: delivery
        )
        deliver!(mail, tenant: tenant, user: user, notifiable: checklist, billed: billed)
      end
    end
  end

  private

  def store_users_for(org_unit)
    org_unit.memberships.includes(:user).select { |m| m.role == "store" }.map(&:user)
  end

  def deliver!(mail, tenant:, user:, notifiable:, billed:)
    status = "sent"

    begin
      mail.deliver_now
    rescue StandardError => e
      status = "failed"
      Rails.logger.warn("[EmailNotifier] #{e.class}: #{e.message}")
    end

    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "email",
      message: mail.subject.to_s.presence || "email",
      status: status,
      billed: billed && status == "sent"
    )
  end
end
