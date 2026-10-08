class Checklist < ApplicationRecord
  include Bilingual

  STATUSES = %w[draft sent].freeze

  belongs_to :tenant
  belongs_to :author, class_name: "User"
  belongs_to :checklist_template, optional: true
  belongs_to :playbook, optional: true
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

    due = scheduled_due
    transaction do
      update!(status: "sent")
      store_ids.uniq.each do |store_id|
        delivery = checklist_deliveries.find_or_create_by!(org_unit_id: store_id) do |record|
          record.status = "pending"
        end
        Vazivo::Assignment.stamp!(delivery, due_at: due)
      end
    end

    NotificationDispatcher.notify_checklist!(self)
    self
  end

  def completion_stats
    total = checklist_deliveries.count
    done = checklist_deliveries.where(status: "completed").count
    pending = total - done
    { total: total, done: done, pending: pending, percent: percent_of(done, total) }
  end

  private

  def percent_of(done, total)
    return 0 if total.zero?

    ((done.to_f / total) * 100).round
  end

  def scheduled_due
    if campaign_on.present?
      Vazivo::Schedule.default_due(tenant, campaign_on.in_time_zone(Vazivo::Schedule::ZONE).change(hour: 18))
    else
      Vazivo::Schedule.default_due(tenant, nil)
    end
  end

  def resolve_store_ids(org_unit_ids)
    units = tenant.org_units.where(id: org_unit_ids)
    units.flat_map { |unit| unit.descendant_stores.pluck(:id) }
  end
end
