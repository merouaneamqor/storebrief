class KbCategory < ApplicationRecord
  include Bilingual

  belongs_to :tenant
  belongs_to :parent, class_name: "KbCategory", optional: true
  has_many :children,
           class_name: "KbCategory",
           foreign_key: :parent_id,
           dependent: :restrict_with_error,
           inverse_of: :parent
  has_many :kb_articles, dependent: :restrict_with_error

  validates :title_fr, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :parent_same_tenant
  validate :parent_not_self_or_descendant

  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position, :title_fr, :id) }

  bilingual_fields :title, :description

  def root?
    parent_id.nil?
  end

  def depth
    n = 0
    node = parent
    while node
      n += 1
      node = node.parent
    end
    n
  end

  # Depth-first ordered list for selects and tree UIs.
  def self.tree_for(tenant)
    roots = tenant.kb_categories.roots.ordered.includes(:children)
    walk = lambda do |nodes, depth, acc|
      nodes.each do |node|
        acc << [ node, depth ]
        kids = node.children.sort_by { |c| [ c.position, c.title_fr.to_s, c.id ] }
        walk.call(kids, depth + 1, acc)
      end
      acc
    end
    walk.call(roots.to_a, 0, [])
  end

  def self.options_for_select(tenant, exclude: nil)
    exclude_id = exclude.respond_to?(:id) ? exclude.id : exclude
    tree_for(tenant).filter_map do |category, depth|
      next if exclude_id.present? && (category.id == exclude_id || category.descendant_of?(exclude_id))

      [ ("› " * depth) + category.title_fr, category.id ]
    end
  end

  def descendant_of?(ancestor_id)
    node = parent
    while node
      return true if node.id == ancestor_id

      node = node.parent
    end
    false
  end

  private

  def parent_same_tenant
    return if parent.blank?
    return if parent.tenant_id == tenant_id

    errors.add(:parent, :invalid)
  end

  def parent_not_self_or_descendant
    return if parent.blank?
    return if id.blank?

    if parent_id == id
      errors.add(:parent, :invalid)
      return
    end

    errors.add(:parent, :invalid) if parent.descendant_of?(id)
  end
end
