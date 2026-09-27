class User < ApplicationRecord
  LOCALES = %w[fr ar].freeze

  has_secure_password

  belongs_to :tenant
  has_many :memberships, dependent: :destroy
  has_many :org_units, through: :memberships
  has_many :authored_communications, class_name: "Communication", foreign_key: :author_id, dependent: :restrict_with_exception, inverse_of: :author
  has_many :notification_logs, dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { scope: :tenant_id }
  validates :locale, inclusion: { in: LOCALES }

  def hq?
    memberships.exists?(role: "hq")
  end

  def store?
    memberships.exists?(role: "store")
  end

  def primary_membership
    memberships.includes(:org_unit).order(:id).first
  end

  def store_org_unit
    memberships.includes(:org_unit).find { |m| m.role == "store" }&.org_unit
  end

  def arabic?
    locale == "ar"
  end
end
