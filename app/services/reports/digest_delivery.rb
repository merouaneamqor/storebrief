module Reports
  # The row lock and successful period key prevent concurrent/repeated sweeps
  # from sending the same digest. Failed SMTP attempts retry at most hourly.
  class DigestDelivery
    def self.deliver_due!(subscription, now: Time.current)
      new(subscription, now).call
    end

    def initialize(subscription, now)
      @subscription = subscription
      @now = now
    end

    def call
      @subscription.with_lock do
        return unless @subscription.due?(@now)

        user = @subscription.user.reload
        unless user.tenant_id == @subscription.tenant_id && Audience.enabled?(user) && user.operational_email_allowed?
          advance_schedule
          return
        end
        range = @subscription.reporting_period(@now)
        period = "#{@subscription.frequency}:#{range.from}:#{range.to}"
        if @subscription.last_sent_period == period
          advance_schedule
          return
        end
        setting = @subscription.tenant.mail_setting_or_build
        billed = setting.delivery_mode == :platform_billed
        return if billed && !PlatformMail.configured?

        deliver(user, range, period, billed)
      end
    end

    private

    def advance_schedule
      @subscription.update!(next_delivery_at: @subscription.next_delivery_after(@now))
    end

    def deliver(user, range, period, billed)
      status = "sent"
      begin
        ReportMailer.digest(subscription: @subscription, date_range: range, now: @now).deliver_now
      rescue StandardError => error
        status = "failed"
        Rails.logger.warn("[ReportDigest] #{error.class}")
      end
      I18n.with_locale(user.locale) do
        NotificationLog.create!(tenant: @subscription.tenant, user: user, notifiable: @subscription, channel: "email",
          message: I18n.t("report_digest.subject", tenant: @subscription.tenant.name), status: status, billed: billed && status == "sent")
      end
      if status == "sent"
        @subscription.update!(last_sent_at: @now, last_sent_period: period,
          next_delivery_at: @subscription.next_delivery_after(@now))
      else
        @subscription.update!(next_delivery_at: @now + 1.hour)
      end
    end
  end
end
