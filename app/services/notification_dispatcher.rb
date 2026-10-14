# Dispatches store alerts in priority order: push (main) → email → WhatsApp (optional).
class NotificationDispatcher
  def self.notify_communication!(communication)
    new.notify_communication!(communication)
  end

  def self.notify_checklist!(checklist)
    new.notify_checklist!(checklist)
  end

  def self.notify_comment_mentions!(comment)
    new.notify_comment_mentions!(comment)
  end

  def notify_communication!(communication)
    tenant = communication.tenant
    PushNotifier.notify_communication!(communication) if tenant.feature?(:push_alerts)
    EmailNotifier.notify_communication!(communication) if tenant.feature?(:email_alerts)
    WhatsappNotifier.notify_communication!(communication) if tenant.feature?(:whatsapp_alerts) && communication.task?
  end

  def notify_checklist!(checklist)
    tenant = checklist.tenant
    PushNotifier.notify_checklist!(checklist) if tenant.feature?(:push_alerts)
    EmailNotifier.notify_checklist!(checklist) if tenant.feature?(:email_alerts)
    WhatsappNotifier.notify_checklist!(checklist) if tenant.feature?(:whatsapp_alerts)
  end

  # Mentions: push is free; email / WhatsApp follow tenant flags and billing rules.
  def notify_comment_mentions!(comment)
    tenant = comment.tenant
    PushNotifier.notify_comment_mentions!(comment) if tenant.feature?(:push_alerts)
    EmailNotifier.notify_comment_mentions!(comment) if tenant.feature?(:email_alerts)
    WhatsappNotifier.notify_comment_mentions!(comment) if tenant.feature?(:whatsapp_alerts)
  end
end
