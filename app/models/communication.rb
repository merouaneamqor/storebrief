class Communication < ApplicationRecord
  include Bilingual

  FORMATS = %w[news task].freeze
  STATUSES = %w[draft sent].freeze

  belongs_to :tenant
  belongs_to :author, class_name: "User"
  has_many :deliveries, dependent: :destroy
  has_many :org_units, through: :deliveries
  has_many :notification_logs, as: :notifiable, dependent: :destroy

  validates :title_fr, :body_fr, presence: true
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }

  bilingual_fields :title, :body

  scope :sent, -> { where(status: "sent") }
  scope :drafts, -> { where(status: "draft") }

  def news?
    format == "news"
  end

  def task?
    format == "task"
  end

  def sent?
    status == "sent"
  end

  def draft?
    status == "draft"
  end

  def send_to!(org_unit_ids)
    store_ids = resolve_store_ids(org_unit_ids)
    raise ArgumentError, "Select at least one store or region" if store_ids.empty?

    transaction do
      update!(status: "sent")
      store_ids.uniq.each do |store_id|
        deliveries.find_or_create_by!(org_unit_id: store_id) do |delivery|
          delivery.status = "pending"
        end
      end
    end

    WhatsappNotifier.notify_communication!(self) if task?
    self
  end

  def completion_stats
    total = deliveries.count
    done = deliveries.where(status: %w[completed read]).count
    { total: total, done: done, pending: total - done }
  end

  private

  def resolve_store_ids(org_unit_ids)
    units = tenant.org_units.where(id: org_unit_ids)
    units.flat_map { |unit| unit.descendant_stores.pluck(:id) }
  end
end
