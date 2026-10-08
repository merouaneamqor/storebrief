class ChecklistTemplate < ApplicationRecord
  include Bilingual

  CATEGORIES = %w[opening closing cleanliness safety promotions equipment store_visit].freeze

  belongs_to :tenant

  validates :category, inclusion: { in: CATEGORIES }
  validates :title_fr, presence: true

  bilingual_fields :title, :description

  def item_defs
    Array(items).map(&:with_indifferent_access)
  end
end
