class PushSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :tenant

  validates :endpoint, presence: true, uniqueness: true
  validates :p256dh, :auth, presence: true
end
