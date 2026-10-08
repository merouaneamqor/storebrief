module Vazivo
  # HQ billing snapshot: platform-sent alerts (email + WhatsApp). Push stays free.
  class Billing
    BILLABLE_CHANNELS = %w[email whatsapp].freeze
    BILLABLE_STATUSES = %w[sent stubbed].freeze

    ChannelStat = Struct.new(
      :channel, :unit_price, :month_count, :month_amount, :prev_count, :total_count,
      keyword_init: true
    )

    Snapshot = Struct.new(
      :mode, :currency,
      :month_count, :month_amount,
      :prev_count, :prev_amount,
      :total_billed_count, :total_billed_amount,
      :channels, :recent_logs, :mail_setting,
      keyword_init: true
    )

    def self.for(tenant, now: Time.current)
      new(tenant, now).snapshot
    end

    def self.currency
      ENV.fetch("VAZIVO_BILLING_CURRENCY", "MAD")
    end

    def self.unit_price_for(channel)
      case channel.to_s
      when "email"
        BigDecimal(ENV.fetch("VAZIVO_EMAIL_UNIT_PRICE", "0.50"))
      when "whatsapp"
        BigDecimal(ENV.fetch("VAZIVO_WHATSAPP_UNIT_PRICE", "0.80"))
      else
        BigDecimal("0")
      end
    end

    # Kept for older call sites / admin copy.
    def self.unit_price
      unit_price_for("email")
    end

    def initialize(tenant, now)
      @tenant = tenant
      @now = now.in_time_zone(Schedule::ZONE)
    end

    def snapshot
      setting = @tenant.mail_setting_or_build
      month_start = @now.beginning_of_month
      prev_start = (month_start - 1.day).beginning_of_month
      prev_end = month_start

      month_counts = counts_in(month_start..)
      prev_counts = counts_in(prev_start...prev_end)
      total_counts = billed_scope.group(:channel).count

      channels = BILLABLE_CHANNELS.map do |channel|
        price = self.class.unit_price_for(channel)
        month = month_counts[channel].to_i
        prev = prev_counts[channel].to_i
        total = total_counts[channel].to_i
        ChannelStat.new(
          channel: channel,
          unit_price: price,
          month_count: month,
          month_amount: month * price,
          prev_count: prev,
          total_count: total
        )
      end

      month_count = channels.sum(&:month_count)
      prev_count = channels.sum(&:prev_count)
      total = channels.sum(&:total_count)

      Snapshot.new(
        mode: setting.delivery_mode,
        currency: self.class.currency,
        month_count: month_count,
        month_amount: channels.sum(&:month_amount),
        prev_count: prev_count,
        prev_amount: channels.sum { |c| c.prev_count * c.unit_price },
        total_billed_count: total,
        total_billed_amount: channels.sum { |c| c.total_count * c.unit_price },
        channels: channels,
        recent_logs: billed_scope.includes(:user).order(created_at: :desc).limit(25),
        mail_setting: setting
      )
    end

    private

    def billed_scope
      @tenant.notification_logs.where(channel: BILLABLE_CHANNELS, billed: true, status: BILLABLE_STATUSES)
    end

    def counts_in(range)
      billed_scope.where(created_at: range).group(:channel).count
    end
  end
end
