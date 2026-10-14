class ChecklistItem < ApplicationRecord
  include Bilingual

  belongs_to :checklist
  has_many :checklist_item_responses, dependent: :destroy

  validates :title_fr, presence: true

  bilingual_fields :title

  def metadata_hash
    (metadata.presence || {}).with_indifferent_access
  end

  def show_if
    metadata_hash[:show_if]
  end

  def template_key
    metadata_hash[:key]
  end
end
