class User < ApplicationRecord
  LOCALES = %w[fr en es ar].freeze

  has_secure_password validations: false

  belongs_to :tenant
  has_many :memberships, dependent: :destroy
  has_many :org_units, through: :memberships
  has_many :authored_communications, class_name: "Communication", foreign_key: :author_id, dependent: :restrict_with_exception, inverse_of: :author
  has_many :audited_visits, class_name: "Visit", foreign_key: :auditor_id, dependent: :restrict_with_exception, inverse_of: :auditor
  has_many :notification_logs, dependent: :nullify
  has_many :push_subscriptions, dependent: :destroy
  has_one :report_subscription, dependent: :destroy

  scope :super_admins, -> { where(super_admin: true) }

  validates :name, presence: true
  validates :email, presence: true, uniqueness: { scope: :tenant_id }
  validates :email, uniqueness: { conditions: -> { super_admins } }, if: :super_admin?
  validates :locale, inclusion: { in: LOCALES }
  validates :password, length: { minimum: 6 }, allow_nil: true
  validates :password, confirmation: true, if: -> { password.present? }

  # Integration tests often create users outside TenantHelpers; accept the
  # privacy notice by default so the CNDP gate does not redirect the suite.
  before_validation :default_test_privacy_acceptance, on: :create, if: -> { Rails.env.test? }

  def default_test_privacy_acceptance
    self.privacy_notice_accepted_at ||= Time.current
  end
  private :default_test_privacy_acceptance

  def hq?
    permission_memberships.any? { |membership| membership.workflow_role == "hq" }
  end

  def store?
    memberships.exists?(role: "store")
  end

  def area?
    permission_memberships.any? { |membership| membership.workflow_role == "area" }
  end

  def permission_memberships
    memberships.includes(:tenant_role, :org_unit).to_a.select { |m| m.org_unit.tenant_id == tenant_id }
  end

  def allows?(capability, org_unit: nil, tenant_wide: false)
    return false if org_unit && org_unit.tenant_id != tenant_id

    permission_memberships.any? do |membership|
      membership.allows?(capability) && (!org_unit || membership.covers?(org_unit)) && (!tenant_wide || membership.tenant_wide?)
    end
  end

  def permitted_store_ids(*capabilities)
    permission_memberships.select { |membership| capabilities.all? { |capability| membership.allows?(capability) } }.flat_map do |membership|
      if membership.role == "hq" && membership.tenant_role_id.nil?
        tenant.org_units.stores.ids
      else
        membership.org_unit.descendant_stores.where(tenant_id: tenant_id).ids
      end
    end.uniq
  end

  def built_in_hq?
    memberships.where(role: "hq", tenant_role_id: nil).exists?
  end

  def primary_membership
    memberships.includes(:org_unit).order(:id).first
  end

  def store_org_unit
    memberships.includes(:org_unit).find { |m| m.role == "store" }&.org_unit
  end

  def area_org_unit
    permission_memberships.find { |m| m.workflow_role == "area" }&.org_unit
  end

  def arabic?
    locale == "ar"
  end

  def privacy_notice_accepted?
    privacy_notice_accepted_at.present?
  end

  def whatsapp_alerts_consented?
    whatsapp_alerts_consent_at.present?
  end

  def operational_email_allowed?
    !operational_email_opt_out?
  end
end
