class Tenant < ApplicationRecord
  has_many :org_units, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :communications, dependent: :destroy
  has_many :checklist_templates, dependent: :destroy
  has_many :checklists, dependent: :destroy
  has_many :notification_logs, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9\-]+\z/ }
end
