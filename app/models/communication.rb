class Communication < ApplicationRecord
  include Bilingual

  FORMATS = %w[news task].freeze
  STATUSES = %w[draft sent].freeze
  SOURCES = %w[compose playbook].freeze
  # Ordered most to least pressing; the index is the sort rank.
  PRIORITIES = %w[urgent important routine].freeze
  DEFAULT_PRIORITY = "routine".freeze

  belongs_to :tenant
  belongs_to :author, class_name: "User"
  belongs_to :playbook, optional: true
  belongs_to :recurrence_parent, class_name: "Communication", optional: true, inverse_of: :occurrences
  has_many :occurrences, class_name: "Communication", foreign_key: :recurrence_parent_id,
                         inverse_of: :recurrence_parent, dependent: :nullify
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
  validates :priority, inclusion: { in: PRIORITIES }
  validate :recurrence_rule_valid

  bilingual_fields :title, :body

  scope :sent, -> { where(status: "sent") }
  scope :drafts, -> { where(status: "draft") }
  scope :recurrence_due, ->(today) { sent.where("recurrence_next_on <= ?", today) }
  # The series source plus every occurrence cloned from it.
  scope :in_series, ->(source_id) { where(id: source_id).or(where(recurrence_parent_id: source_id)) }

  # SQL ordering expression: urgent first, routine last.
  PRIORITY_ORDER_SQL = Arel.sql(
    "CASE communications.priority " +
    PRIORITIES.each_with_index.map { |key, rank| "WHEN '#{key}' THEN #{rank}" }.join(" ") +
    " ELSE #{PRIORITIES.size} END"
  )
  scope :by_priority, -> { order(PRIORITY_ORDER_SQL) }

  def self.priority_rank(priority)
    PRIORITIES.index(priority.to_s) || PRIORITIES.size
  end

  before_validation :apply_source_default
  before_validation :apply_priority_default
  before_validation :clear_recurrence_unless_task

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

  def priority_rank
    self.class.priority_rank(priority)
  end

  def questions?
    communication_questions.any?
  end

  def recurring?
    recurrence_parent_id.nil? && recurrence_rule.present?
  end

  def occurrence?
    recurrence_parent_id.present?
  end

  def recurrence_active?
    recurring? && recurrence_next_on.present?
  end

  def series_source
    recurrence_parent || self
  end

  # Form input: { frequency:, interval:, weekdays: [], ends_on: }
  def recurrence_attributes=(attrs)
    self.recurrence_rule = Vazivo::Recurrence.normalize(attrs)
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

    Vazivo::Recurrence.arm!(self) if recurring?
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

  # Only tasks carry a priority; notes are always routine.
  def apply_priority_default
    self.priority = DEFAULT_PRIORITY if priority.blank? || !task?
  end

  def clear_recurrence_unless_task
    self.recurrence_rule = {} unless task?
  end

  def recurrence_rule_valid
    return if recurrence_rule.blank?

    errors.add(:recurrence_rule, :invalid) if occurrence? || Vazivo::Recurrence.errors_for(recurrence_rule).any?
  end

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
