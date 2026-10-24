class DeliveryRead < ApplicationRecord
  belongs_to :tenant
  belongs_to :delivery
  belongs_to :user

  validates :read_at, presence: true
  validates :user_id, uniqueness: { scope: :delivery_id }
  validate :tenant_matches_delivery
  validate :user_belongs_to_delivery_store

  before_validation :assign_tenant_from_delivery, on: :create
  before_validation :assign_read_at, on: :create
  after_create :record_audit_event!

  # Append-only: once marked read, keep the first receipt.
  def readonly?
    persisted?
  end

  private

  def assign_tenant_from_delivery
    self.tenant_id ||= delivery&.communication&.tenant_id
  end

  def assign_read_at
    self.read_at ||= Time.current
  end

  def tenant_matches_delivery
    return if delivery.blank? || tenant_id.blank?

    expected = delivery.communication&.tenant_id
    return if expected.blank? || expected == tenant_id

    errors.add(:tenant, :invalid)
  end

  def user_belongs_to_delivery_store
    return if user.blank? || delivery.blank?

    store_id = delivery.org_unit_id
    return if user.memberships.exists?(org_unit_id: store_id, role: "store")

    errors.add(:user, :invalid)
  end

  def record_audit_event!
    delivery.record_event!(
      "read_receipt",
      { user_id: user_id, read_at: read_at.iso8601 },
      actor: user
    )
  end
end
