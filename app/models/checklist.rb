class Checklist < ApplicationRecord
  include Bilingual

  STATUSES = %w[draft sent].freeze

  belongs_to :tenant
  belongs_to :author, class_name: "User"
  belongs_to :checklist_template, optional: true
  has_many :checklist_items, -> { order(:position) }, dependent: :destroy, inverse_of: :checklist
  has_many :checklist_deliveries, dependent: :destroy
  has_many :org_units, through: :checklist_deliveries
  has_many :notification_logs, as: :notifiable, dependent: :destroy

  validates :title_fr, presence: true
  validates :status, inclusion: { in: STATUSES }

  bilingual_fields :title, :description

  scope :sent, -> { where(status: "sent") }

  def sent?
    status == "sent"
  end

  def draft?
    status == "draft"
  end

  def self.build_from_template(template, author:)
    checklist = template.tenant.checklists.new(
      author: author,
      checklist_template: template,
      title_fr: template.title_fr,
      title_ar: template.title_ar,
      description_fr: template.description_fr,
      description_ar: template.description_ar,
      status: "draft"
    )
    template.item_defs.each_with_index do |item, index|
      checklist.checklist_items.build(
        position: index,
        title_fr: item[:title_fr],
        title_ar: item[:title_ar],
        requires_photo: ActiveModel::Type::Boolean.new.cast(item[:requires_photo])
      )
    end
    checklist
  end

  def send_to!(org_unit_ids)
    store_ids = resolve_store_ids(org_unit_ids)
    raise ArgumentError, I18n.t("errors.select_targets") if store_ids.empty?

    transaction do
      update!(status: "sent")
      store_ids.uniq.each do |store_id|
        checklist_deliveries.find_or_create_by!(org_unit_id: store_id) do |delivery|
          delivery.status = "pending"
        end
      end
    end

    WhatsappNotifier.notify_checklist!(self)
    self
  end

  def completion_stats
    total = checklist_deliveries.count
    done = checklist_deliveries.where(status: "completed").count
    { total: total, done: done, pending: total - done }
  end

  private

  def resolve_store_ids(org_unit_ids)
    units = tenant.org_units.where(id: org_unit_ids)
    units.flat_map { |unit| unit.descendant_stores.pluck(:id) }
  end
end
