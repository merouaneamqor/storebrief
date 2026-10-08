class ChecklistItemResponse < ApplicationRecord
  belongs_to :checklist_delivery
  belongs_to :checklist_item
  has_one_attached :photo

  validates :checklist_item_id, uniqueness: { scope: :checklist_delivery_id }

  def completed?
    completed
  end
end
