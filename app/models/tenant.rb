class Tenant < ApplicationRecord
  has_many :org_units, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :communications, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9\-]+\z/ }
end
