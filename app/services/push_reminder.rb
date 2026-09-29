# frozen_string_literal: true

# Daily digests for store users who still have open work.
class PushReminder
  MIN_AGE = 12.hours
  LOOKBACK = 14.days

  def self.notify_pending!
    new.notify_pending!
  end

  def notify_pending!
    return 0 unless WebPushConfig.configured?

    remind_briefs! + remind_checklists!
  end

  private

  def remind_briefs!
    sent = 0
    pending_briefs.find_each do |delivery|
      communication = delivery.communication
      users = store_users(delivery.org_unit)
      next if users.empty?
      next if pushed_today?(communication, users)

      users.each do |user|
        next if user.push_subscriptions.empty?

        title, body = reminder_copy_brief(communication, user)
        PushNotifier.deliver_to_user!(
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
    sent
  end

  def remind_checklists!
    sent = 0
    pending_checklists.find_each do |delivery|
      checklist = delivery.checklist
      users = store_users(delivery.org_unit)
      next if users.empty?
      next if pushed_today?(checklist, users)

      users.each do |user|
        next if user.push_subscriptions.empty?

        title, body = reminder_copy_checklist(checklist, user)
        PushNotifier.deliver_to_user!(
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
    sent
  end

  def pending_briefs
    Delivery
      .joins(:communication)
      .where(status: "pending", communications: { status: "sent" })
      .where(deliveries: { created_at: LOOKBACK.ago..MIN_AGE.ago })
      .includes(communication: :tenant, org_unit: { memberships: :user })
  end

  def pending_checklists
    ChecklistDelivery
      .joins(:checklist)
      .where(status: "pending", checklists: { status: "sent" })
      .where(checklist_deliveries: { created_at: LOOKBACK.ago..MIN_AGE.ago })
      .includes(checklist: :tenant, org_unit: { memberships: :user })
  end

  def store_users(org_unit)
    org_unit.memberships.select { |m| m.role == "store" }.map(&:user)
  end

  def pushed_today?(notifiable, users)
    NotificationLog
      .where(notifiable: notifiable, channel: "web_push", user_id: users.map(&:id))
      .where(created_at: Time.current.beginning_of_day..)
      .exists?
  end

  def reminder_copy_brief(communication, user)
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
