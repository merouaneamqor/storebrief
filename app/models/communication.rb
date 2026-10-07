class Communication < ApplicationRecord
  include Bilingual

  FORMATS = %w[news task].freeze
  STATUSES = %w[draft sent].freeze
  SOURCES = %w[compose playbook].freeze

  belongs_to :tenant
  belongs_to :author, class_name: "User"
  belongs_to :playbook, optional: true
  has_many :deliveries, dependent: :destroy
  has_many :org_units, through: :deliveries
  has_many :notification_logs, as: :notifiable, dependent: :destroy
  has_many :communication_questions, -> { ordered }, dependent: :destroy, inverse_of: :communication

  accepts_nested_attributes_for :communication_questions, allow_destroy: true, reject_if: :reject_blank_question?

  validates :title_fr, presence: true
  validates :body_fr, presence: true, unless: :questions_present?
  validates :format, inclusion: { in: FORMATS }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }

  bilingual_fields :title, :body

  scope :sent, -> { where(status: "sent") }
  scope :drafts, -> { where(status: "draft") }

  before_validation :apply_source_default

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

  def questions?
    communication_questions.any?
  end

  def send_to!(org_unit_ids)
    store_ids = resolve_store_ids(org_unit_ids)
    raise ArgumentError, I18n.t("errors.select_targets") if store_ids.empty?

    due = Vazivo::Schedule.default_due(tenant, due_at)
    transaction do
      update!(status: "sent", due_at: due)
      store_ids.uniq.each do |store_id|
        delivery = deliveries.find_or_create_by!(org_unit_id: store_id) do |record|
          record.status = "pending"
        end
        Vazivo::Assignment.stamp!(delivery, due_at: due)
      end
    end

    NotificationDispatcher.notify_communication!(self)
    self
  end

  def completion_stats
    total = deliveries.count
    done = deliveries.where(status: %w[completed read]).count
    pending = total - done
    { total: total, done: done, pending: pending, percent: percent_of(done, total) }
  end

  private

  def apply_source_default
    self.source = "compose" if source.blank?
  end

  def questions_present?
    communication_questions.reject(&:marked_for_destruction?).any? { |question| question.title_fr.present? }
  end

  def reject_blank_question?(attrs)
    attrs["title_fr"].blank? && attrs["title_ar"].blank? && ActiveModel::Type::Boolean.new.cast(attrs["_destroy"]).blank?
  end

  def percent_of(done, total)
    return 0 if total.zero?

    ((done.to_f / total) * 100).round
  end

  def resolve_store_ids(org_unit_ids)
    units = tenant.org_units.where(id: org_unit_ids)
    units.flat_map { |unit| unit.descendant_stores.pluck(:id) }
  end
end
