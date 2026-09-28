class WhatsappNotifier
  def self.notify_communication!(communication)
    new.notify_communication!(communication)
  end

  def self.notify_checklist!(checklist)
    new.notify_checklist!(checklist)
  end

  def notify_communication!(communication)
    return unless communication.tenant.feature?(:whatsapp_alerts)

    communication.deliveries.includes(org_unit: { memberships: :user }).find_each do |delivery|
      recipients_for(delivery.org_unit).each do |user|
        create_log!(
          tenant: communication.tenant,
          user: user,
          notifiable: communication,
          message: message_for_communication(communication, user)
        )
      end
    end
  end

  def notify_checklist!(checklist)
    return unless checklist.tenant.feature?(:whatsapp_alerts)

    checklist.checklist_deliveries.includes(org_unit: { memberships: :user }).find_each do |delivery|
      recipients_for(delivery.org_unit).each do |user|
        create_log!(
          tenant: checklist.tenant,
          user: user,
          notifiable: checklist,
          message: message_for_checklist(checklist, user, delivery)
        )
      end
    end
  end

  private

  def recipients_for(org_unit)
    org_unit.memberships.includes(:user).select { |m| m.role == "store" }.map(&:user).select { |u| u.whatsapp_phone.present? }
  end

  def create_log!(tenant:, user:, notifiable:, message:)
    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "whatsapp",
      phone: user.whatsapp_phone,
      message: message,
      status: "stubbed"
    )
  end

  def message_for_communication(communication, user)
    locale = user.locale
    title = communication.localized_value(:title, locale: locale)
    if locale == "ar"
      "مهمة جديدة: #{title}\nافتح StoreBrief لإكمالها."
    else
      "Nouvelle tâche: #{title}\nOuvrez StoreBrief pour la terminer."
    end
  end

  def message_for_checklist(checklist, user, delivery)
    locale = user.locale
    title = checklist.localized_value(:title, locale: locale)
    path = "/checklists/deliveries/#{delivery.id}"
    if locale == "ar"
      "قائمة تحقق جديدة: #{title}\nالرابط: #{path}"
    else
      "Nouvelle checklist: #{title}\nLien: #{path}"
    end
  end
end
