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

  def notify_communication!(communication)
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
      message: "#{payload[:title]} — #{payload[:body]}",
      status: "sent"
    )
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    subscription.destroy!
    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "web_push",
      message: "#{payload[:title]} — #{payload[:body]}",
      status: "gone"
    )
  rescue StandardError => error
    Rails.logger.warn("[PushNotifier] #{error.class}: #{error.message}")
    NotificationLog.create!(
      tenant: tenant,
      user: user,
      notifiable: notifiable,
      channel: "web_push",
      message: "#{payload[:title]} — #{payload[:body]}",
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
end
