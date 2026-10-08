class ChecklistItem < ApplicationRecord
  include Bilingual

  belongs_to :checklist
  has_many :checklist_item_responses, dependent: :destroy

  validates :title_fr, presence: true

  bilingual_fields :title
end
