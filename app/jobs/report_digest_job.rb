class ReportDigestJob < ApplicationJob
  queue_as :default

  def perform
    now = Time.current
    ReportSubscription.where(enabled: true).where("next_delivery_at <= ?", now).find_each do |subscription|
      begin
        Reports::DigestDelivery.deliver_due!(subscription, now: now)
      rescue StandardError => error
        Rails.logger.error("[ReportDigestJob] subscription=#{subscription.id} #{error.class}")
      end
    end
  end
end
