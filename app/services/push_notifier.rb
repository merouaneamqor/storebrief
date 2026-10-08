# frozen_string_literal: true

require "web-push"

class PushNotifier
  def self.notify_communication!(communication)
    new.notify_communication!(communication)
  end

  def self.notify_checklist!(checklist)
    new.notify_checklist!(checklist)
  end

  def self.deliver_to_user!(**)
    new.deliver_to_user!(**)
  end

  def self.remind_communication!(communication)
    new.remind_communication!(communication)
  end

  def self.remind_checklist!(checklist)
    new.remind_checklist!(checklist)
  end

  def notify_communication!(communication)
    return unless communication.tenant.feature?(:push_alerts)
    return unless WebPushConfig.configured?

    communication.deliveries.includes(org_unit: { memberships: :user }).find_each do |delivery|
      store_users_for(delivery.org_unit).each do |user|
        title, body = copy_for_communication(communication, user)
        deliver_to_user!(
          user: user,
          tenant: communication.tenant,
          notifiable: communication,
          title: title,
          body: body,
          url: "/inbox/#{delivery.id}"
        )
      end
    end
  end

  def notify_checklist!(checklist)
    return unless checklist.tenant.feature?(:push_alerts)
    return unless WebPushConfig.configured?

    checklist.checklist_deliveries.includes(org_unit: { memberships: :user }).find_each do |delivery|
      store_users_for(delivery.org_unit).each do |user|
        title, body = copy_for_checklist(checklist, user)
        deliver_to_user!(
          user: user,
          tenant: checklist.tenant,
          notifiable: checklist,
          title: title,
          body: body,
          url: "/checklists/deliveries/#{delivery.id}"
        )
      end
    end
  end

  # HQ / super-admin: ping stores that still have this item open.
  def remind_communication!(communication)
    return 0 unless WebPushConfig.configured?

    sent = 0
    skipped = 0
    communication.deliveries.pending.includes(org_unit: { memberships: { user: :push_subscriptions } }).find_each do |delivery|
      users = store_users_for(delivery.org_unit)
      if users.empty?
        Rails.logger.info("[PushNotifier] remind brief##{communication.id} skip #{delivery.org_unit.name}: no store user")
        skipped += 1
        next
      end

      users.each do |user|
        if user.push_subscriptions.empty?
          Rails.logger.info("[PushNotifier] remind brief##{communication.id} skip #{user.email}: no device")
          skipped += 1
          next
        end

        title, body = reminder_copy_communication(communication, user)
        deliver_to_user!(
          user: user,
          tenant: communication.tenant,
          notifiable: communication,
          title: title,
          body: body,
          url: "/inbox/#{delivery.id}"
        )
        sent += 1
      end
    end
    Rails.logger.info("[PushNotifier] remind brief##{communication.id} sent=#{sent} skipped=#{skipped}")
    sent
  end

  def remind_checklist!(checklist)
    return 0 unless WebPushConfig.configured?

    sent = 0
    skipped = 0
    checklist.checklist_deliveries.pending.includes(org_unit: { memberships: { user: :push_subscriptions } }).find_each do |delivery|
      users = store_users_for(delivery.org_unit)
      if users.empty?
        Rails.logger.info("[PushNotifier] remind checklist##{checklist.id} skip #{delivery.org_unit.name}: no store user")
        skipped += 1
        next
      end

      users.each do |user|
        if user.push_subscriptions.empty?
          Rails.logger.info("[PushNotifier] remind checklist##{checklist.id} skip #{user.email}: no device")
          skipped += 1
          next
        end

        title, body = reminder_copy_checklist(checklist, user)
        deliver_to_user!(
          user: user,
          tenant: checklist.tenant,
          notifiable: checklist,
          title: title,
          body: body,
          url: "/checklists/deliveries/#{delivery.id}"
        )
        sent += 1
      end
    end
    Rails.logger.info("[PushNotifier] remind checklist##{checklist.id} sent=#{sent} skipped=#{skipped}")
    sent
  end

  def deliver_to_user!(user:, tenant:, notifiable:, title:, body:, url:)
    subscriptions = user.push_subscriptions.where(tenant_id: tenant.id)
    return if subscriptions.empty?

    payload = {
      title: title,
      body: body,
      url: url,
      icon: "/icon.png",
      badge: "/icon.png"
    }

    subscriptions.find_each do |subscription|
      send_one!(subscription, tenant:, notifiable:, payload:)
    end
  end

  private

  def store_users_for(org_unit)
    org_unit.memberships.includes(:user).select { |m| m.role == "store" }.map(&:user)
  end

  def send_one!(subscription, tenant:, notifiable:, payload:)
    user = subscription.user

    WebPush.payload_send(
      message: JSON.generate(payload),
      endpoint: subscription.endpoint,
      p256dh: subscription.p256dh,
      auth: subscription.auth,
      vapid: WebPushConfig.vapid_options
    )

    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "web_push",
      message: "#{payload[:title]}: #{payload[:body]}",
      status: "sent"
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    subscription.destroy!
    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "web_push",
      message: "#{payload[:title]}: #{payload[:body]}",
      status: "gone"
    )
  rescue StandardError => error
    Rails.logger.warn("[PushNotifier] #{error.class}: #{error.message}")
    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "web_push",
      message: "#{payload[:title]}: #{payload[:body]}",
      status: "failed"
    )
  end

  def copy_for_communication(communication, user)
    locale = user.locale
    title = communication.localized_value(:title, locale: locale)
    if communication.task?
      if locale == "ar"
        [ "مهمة جديدة", title.to_s ]
      elsif locale == "es"
        [ "Nueva tarea", title.to_s ]
      elsif locale == "en"
        [ "New task", title.to_s ]
      else
        [ "Nouvelle tâche", title.to_s ]
      end
    elsif locale == "ar"
      [ "خبر جديد", title.to_s ]
    elsif locale == "es"
      [ "Nueva nota", title.to_s ]
    elsif locale == "en"
      [ "New note", title.to_s ]
    else
      [ "Nouvelle info", title.to_s ]
    end
  end

  def copy_for_checklist(checklist, user)
    locale = user.locale
    title = checklist.localized_value(:title, locale: locale)
    if locale == "ar"
      [ "قائمة تحقق جديدة", title.to_s ]
    elsif locale == "es"
      [ "Nueva checklist", title.to_s ]
    elsif locale == "en"
      [ "New checklist", title.to_s ]
    else
      [ "Nouvelle checklist", title.to_s ]
    end
  end

  def reminder_copy_communication(communication, user)
    locale = user.locale
    title = communication.localized_value(:title, locale: locale)
    case locale
    when "ar" then [ "تذكير", title.to_s ]
    when "es" then [ "Recordatorio", title.to_s ]
    when "en" then [ "Reminder", title.to_s ]
    else [ "Rappel", title.to_s ]
    end
  end

  def reminder_copy_checklist(checklist, user)
    locale = user.locale
    title = checklist.localized_value(:title, locale: locale)
    case locale
    when "ar" then [ "تذكير", title.to_s ]
    when "es" then [ "Recordatorio", title.to_s ]
    when "en" then [ "Reminder", title.to_s ]
    else [ "Rappel", title.to_s ]
    end
  end
end
