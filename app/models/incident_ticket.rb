class IncidentTicket < ApplicationRecord
  PRIORITIES = %w[urgent important routine].freeze
  TRANSITIONS = {
    "open" => %w[in_progress resolved],
    "in_progress" => %w[open resolved],
    "resolved" => %w[open closed],
    "closed" => %w[open]
  }.freeze

  belongs_to :tenant
  belongs_to :org_unit
  belongs_to :ticket_category
  belongs_to :author, class_name: "User"
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :source, polymorphic: true, optional: true
  has_many :ticket_events, dependent: :restrict_with_exception
  validates :title, presence: true, length: { maximum: 160 }
  validates :description, presence: true, length: { maximum: 5000 }
  validates :department, :due_at, presence: true
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: TRANSITIONS.keys }
  validates :source_type, inclusion: { in: %w[Delivery ChecklistItemResponse] }, allow_nil: true
  validate :tenant_boundaries
  before_validation :snapshot_sla, on: :create
  after_create :record_creation

  scope :unresolved, -> { where(status: %w[open in_progress]) }
  scope :breached, ->(now = Time.current) {
    where("(resolved_at IS NULL AND due_at < ?) OR resolved_at > due_at", now)
  }

  def breached?(now = Time.current)
    (resolved_at || now) > due_at
  end

  def workflow!(actor:, status:, assignee:)
    with_lock do
      previous_status = self.status
      previous_assignee = assignee_id
      if status != previous_status && !TRANSITIONS.fetch(previous_status).include?(status)
        errors.add(:status, :invalid)
        raise ActiveRecord::RecordInvalid, self
      end
      self.status = status
      self.assignee = assignee
      self.resolved_at = %w[resolved closed].include?(status) ? (resolved_at || Time.current) : nil
      save!
      ticket_events.create!(actor: actor, kind: "status", from_value: previous_status, to_value: status) if previous_status != status
      if previous_assignee != assignee_id
        ticket_events.create!(actor: actor, kind: "assignee", from_value: previous_assignee, to_value: assignee_id)
      end
    end
  end

  private

  def snapshot_sla
    return unless ticket_category

    self.department = ticket_category.department
    self.due_at = Time.current + ticket_category.sla_hours.to_i.hours
  end

  def record_creation
    ticket_events.create!(actor: author, kind: "created", to_value: status)
  end

  def tenant_boundaries
    records = [ org_unit, ticket_category, author, assignee ].compact
    errors.add(:base, :invalid) unless records.all? { |record| record.tenant_id == tenant_id } && org_unit&.store?
    if assignee && !assignee.allows?(:monitor, org_unit: org_unit)
      errors.add(:assignee, :invalid)
    end
    return unless source && (new_record? || source_id_changed? || source_type_changed? || org_unit_id_changed?)

    valid = case source
    when Delivery
      source.communication.tenant_id == tenant_id && source.org_unit_id == org_unit_id && source.verdict == "non_conforme"
    when ChecklistItemResponse
      delivery = source.checklist_delivery
      delivery.checklist.tenant_id == tenant_id && delivery.org_unit_id == org_unit_id && source.checklist_item.checklist_id == delivery.checklist_id
    else
      false
    end
    errors.add(:source, :invalid) unless valid
  end
end
