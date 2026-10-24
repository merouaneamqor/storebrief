class ChecklistDelivery < ApplicationRecord
  include Vazivo::Execution

  STATUSES = %w[pending completed].freeze

  belongs_to :checklist
  belongs_to :org_unit
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  has_many :checklist_delivery_comments, -> { order(:created_at, :id) }, dependent: :restrict_with_exception
  has_many :checklist_delivery_events, -> { order(:created_at, :id) }, dependent: :restrict_with_exception
  has_many :checklist_item_responses, dependent: :destroy
  has_many :escalation_events, as: :subject, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :org_unit_id, uniqueness: { scope: :checklist_id }
  validates :verdict, inclusion: { in: Delivery::VERDICTS }, allow_nil: true
  validates :verdict_note, length: { maximum: 4_000 }
  after_update :record_status_history, if: :saved_change_to_status?

  scope :pending, -> { where(status: "pending") }
  scope :for_store, ->(org_unit) { where(org_unit_id: org_unit.id) }

  def pending?
    status == "pending"
  end

  def completed?
    status == "completed"
  end

  def ready_to_complete?
    responses = checklist_item_responses.includes(photo_attachment: :blob).index_by(&:checklist_item_id)

    checklist.checklist_items.all? do |item|
      response = responses[item.id]
      next false unless response&.completed?
      next false if item.requires_photo? && !response.evidence_attached?

      true
    end
  end

  def missing_required_evidence?
    responses = checklist_item_responses.includes(photo_attachment: :blob).index_by(&:checklist_item_id)

    checklist.checklist_items.any? do |item|
      next false unless item.requires_photo?

      response = responses[item.id]
      !response&.evidence_attached?
    end
  end

  def complete_if_ready!
    return false unless pending?
    return false unless ready_to_complete?

    update!(status: "completed", completed_at: Time.current)
    true
  end

  def apply_review_verdict!(value, note:, by:)
    raise ArgumentError, I18n.t("morocco.verdict.invalid") unless Delivery::VERDICTS.include?(value.to_s)
    unless by.tenant_id == checklist.tenant_id && %i[verdicts escalate].all? { |cap| by.allows?(cap, org_unit: org_unit) }
      raise ArgumentError, I18n.t("auth.hq_required")
    end

    @review_actor = by
    with_lock do
      attributes = { verdict: value, verdict_note: note.to_s.strip.presence, validated_by: by, validated_at: Time.current }
      attributes.merge!(status: "pending", completed_at: nil) if value == "non_conforme"
      update!(attributes)
      checklist_item_responses.update_all(completed: false) if value == "non_conforme"
      record_review_event!("verdict", { verdict: verdict, note: verdict_note }, actor: by)
    end
  ensure
    @review_actor = nil
  end

  def record_review_event!(kind, payload, actor: nil)
    checklist_delivery_events.create!(tenant_id: checklist.tenant_id, kind: kind, payload: payload, actor: actor, created_at: Time.current)
  end

  private

  def record_status_history
    candidate = @review_actor || Current.user
    actor = candidate if candidate&.tenant_id == checklist.tenant_id
    record_review_event!("status", { from: status_before_last_save, to: status }, actor: actor)
  end
end
