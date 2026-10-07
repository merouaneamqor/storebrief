class User < ApplicationRecord
  LOCALES = %w[fr en es ar].freeze

  has_secure_password validations: false

  belongs_to :tenant
  has_many :memberships, dependent: :destroy
  has_many :org_units, through: :memberships
  has_many :authored_communications, class_name: "Communication", foreign_key: :author_id, dependent: :restrict_with_exception, inverse_of: :author
  has_many :notification_logs, dependent: :nullify
  has_many :push_subscriptions, dependent: :destroy

  scope :super_admins, -> { where(super_admin: true) }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { scope: :tenant_id }
  validates :email, uniqueness: { conditions: -> { super_admins } }, if: :super_admin?
  validates :locale, inclusion: { in: LOCALES }
  validates :password, length: { minimum: 6 }, allow_nil: true
  validates :password, confirmation: true, if: -> { password.present? }

  def hq?
    memberships.exists?(role: "hq")
  end

  def store?
    memberships.exists?(role: "store")
  end

  def area?
    memberships.exists?(role: "area")
  end

  def primary_membership
    memberships.includes(:org_unit).order(:id).first
  end

  def store_org_unit
    memberships.includes(:org_unit).find { |m| m.role == "store" }&.org_unit
  end

  def area_org_unit
    memberships.includes(:org_unit).find { |m| m.role == "area" }&.org_unit
  end

  # Stores the user can act on: own store (store role), descendant stores of
  # any area membership (area role), or every tenant store (HQ / super admin).
  def manageable_stores
    units = memberships.includes(:org_unit).map(&:org_unit).compact
    scopes = units.flat_map do |unit|
      unit.store? ? [ unit ] : unit.descendant_stores.to_a
    end
    scopes.concat(tenant.org_units.stores.to_a) if hq? || super_admin?
    scopes.uniq
  end

  def manageable_store_ids
    manageable_stores.map(&:id)
  end

  def arabic?
    locale == "ar"
  end
end
