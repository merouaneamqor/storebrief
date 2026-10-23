module Vazivo
  # Engagement only uses free push. Tenant email/WhatsApp defaults do not opt in
  # to new billable alerts.
  class FeedNotifications
    def self.comment!(comment)
      subject = comment.subject
      recipient = subject.is_a?(Delivery) ? subject.communication.author : subject.user
      notify(comment, recipient, "comment") unless recipient == comment.user
    end

    def self.published!(post)
      notify(post, post.user, "published")
    end

    def self.notify(entry, recipient, event)
      return unless entry.tenant.feature?(:push_alerts) && WebPushConfig.configured?

      PushNotifier.deliver_to_user!(
        user: recipient, tenant: entry.tenant, notifiable: entry,
        title: I18n.t("feed_engagement.notification_#{event}", locale: recipient.locale),
        body: entry.body.truncate(160),
        url: recipient.hq? ? "/feed_moderation" : "/newsfeed"
      )
    end
    private_class_method :notify
  end
end
