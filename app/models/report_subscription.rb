class ReportSubscription < ApplicationRecord
  FREQUENCIES = %w[weekly monthly].freeze

  belongs_to :tenant
  belongs_to :user
  # Retain billed notification history if a subscription/user is removed.
  has_many :notification_logs, as: :notifiable

  validates :user_id, uniqueness: true
  validates :frequency, inclusion: { in: FREQUENCIES }
  validate :user_belongs_to_tenant
  before_validation :schedule_delivery

  def due?(now)
    enabled? && next_delivery_at.present? && next_delivery_at <= now
  end

  def next_delivery_after(now)
    local = now.in_time_zone(Vazivo::Schedule::ZONE)
    date = frequency == "monthly" ? local.to_date.beginning_of_month : local.to_date.beginning_of_week
    candidate = date.in_time_zone(Vazivo::Schedule::ZONE).change(hour: 8)
    if candidate <= local
      date = frequency == "monthly" ? date.next_month : date + 1.week
      candidate = date.in_time_zone(Vazivo::Schedule::ZONE).change(hour: 8)
    end
    candidate
  end

  def reporting_period(now)
    date = now.in_time_zone(Vazivo::Schedule::ZONE).to_date
    last = (frequency == "monthly" ? date.beginning_of_month : date.beginning_of_week) - 1.day
    first = frequency == "monthly" ? last.beginning_of_month : last.beginning_of_week
    Reports::DateRange.new(from: first.iso8601, to: last.iso8601)
  end

  private

  def schedule_delivery
    if !enabled?
      self.next_delivery_at = nil
    elsif new_record? || will_save_change_to_enabled? || will_save_change_to_frequency?
      self.next_delivery_at = next_delivery_after(Vazivo::Schedule.now)
    end
  end

  def user_belongs_to_tenant
    errors.add(:user, :invalid) if user && user.tenant_id != tenant_id
  end
end
