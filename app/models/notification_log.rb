class NotificationLog < ApplicationRecord
  CHANNELS = %w[whatsapp web_push].freeze
  STATUSES = %w[stubbed sent failed gone].freeze

  belongs_to :tenant
  belongs_to :user, optional: true
  belongs_to :notifiable, polymorphic: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :message, presence: true
end
