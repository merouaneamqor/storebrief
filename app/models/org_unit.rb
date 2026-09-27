class OrgUnit < ApplicationRecord
  UNIT_TYPES = %w[region area store].freeze

  belongs_to :tenant
  belongs_to :parent, class_name: "OrgUnit", optional: true
  has_many :children, class_name: "OrgUnit", foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :deliveries, dependent: :destroy

  validates :name, presence: true
  validates :unit_type, inclusion: { in: UNIT_TYPES }
  validate :parent_same_tenant

  scope :regions, -> { where(unit_type: "region") }
  scope :areas, -> { where(unit_type: "area") }
  scope :stores, -> { where(unit_type: "store") }
  scope :roots, -> { where(parent_id: nil) }

  def store?
    unit_type == "store"
  end

  def descendant_stores
    return OrgUnit.none unless tenant_id
    return OrgUnit.where(id: id) if store?

    store_ids = collect_store_ids
    OrgUnit.where(id: store_ids)
  end

  private

  def collect_store_ids
    ids = []
    queue = children.to_a
    while queue.any?
      unit = queue.shift
      if unit.store?
        ids << unit.id
      else
        queue.concat(unit.children.to_a)
      end
    end
    ids
  end

  def parent_same_tenant
    return if parent.blank?
    return if parent.tenant_id == tenant_id

    errors.add(:parent, "must belong to the same tenant")
  end
end
