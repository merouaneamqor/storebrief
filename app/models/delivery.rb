class Delivery < ApplicationRecord
  include Vazivo::Execution

  STATUSES = %w[pending pending_approval completed read].freeze
  AWARENESS_STEPS = %w[received read understood in_progress done].freeze
  VERDICTS = %w[conforme improve non_conforme].freeze
  APPROVAL_REJECT_VERDICT = "non_conforme".freeze

  belongs_to :communication
  belongs_to :org_unit
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :acknowledged_by, class_name: "User", optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  belongs_to :dependency_cleared_by, class_name: "User", optional: true
  has_many :delivery_answers, dependent: :destroy
  has_many :delivery_events, dependent: :delete_all
  has_many :delivery_comments, dependent: :delete_all
  has_many :delivery_reads, dependent: :delete_all
  has_many :escalation_events, as: :subject, dependent: :destroy
  has_one :corrective_communication, class_name: "Communication", foreign_key: :source_delivery_id,
                                    inverse_of: :source_delivery, dependent: :nullify
  has_one_attached :photo_before
  has_one_attached :photo_after
  has_many_attached :proof_files

  PROOF_MAX_BYTES = 10.megabytes
  PROOF_MAX_COUNT = 10
  PROOF_IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  PROOF_FILE_TYPES = (PROOF_IMAGE_TYPES + %w[
    application/pdf text/plain text/csv
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ]).freeze

  validates :status, inclusion: { in: STATUSES }
  validates :org_unit_id, uniqueness: { scope: :communication_id }

  validate :acceptable_proof

  after_update :log_history_changes

  scope :pending, -> { where(status: "pending") }
  scope :for_store, ->(org_unit) { where(org_unit_id: org_unit.id) }
  # A store sees one instance per recurring series: the newest one it received.
  scope :current_instances, -> {
    joins(:communication).where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM deliveries newer
        JOIN communications newer_c ON newer_c.id = newer.communication_id
        WHERE newer.org_unit_id = deliveries.org_unit_id
          AND newer_c.status = 'sent'
          AND newer_c.id > communications.id
          AND COALESCE(newer_c.recurrence_parent_id, newer_c.id) = COALESCE(communications.recurrence_parent_id, communications.id)
          AND newer_c.recurrence_parent_id IS NOT NULL
      )
    SQL
  }

  def complete!
    ensure_not_dependency_blocked!
    ensure_required_answers!
    ensure_proof!
    return submit_for_approval! if communication.requires_approval?

    attrs = { status: "completed", completed_at: Time.current, awareness: "done" }
    attrs.merge!(scored_attrs) if communication.questions?
    update!(attrs)
  end

  def submit_for_approval!
    ensure_not_dependency_blocked!
    ensure_required_answers!
    ensure_proof!
    raise ArgumentError, I18n.t("morocco.approval.not_required") unless communication.requires_approval?
    raise ArgumentError, I18n.t("morocco.approval.already_submitted") if pending_approval?
    raise ArgumentError, I18n.t("morocco.approval.already_done") if finished?

    attrs = {
      status: "pending_approval",
      completed_at: nil,
      awareness: "in_progress",
      verdict: nil,
      verdict_note: nil,
      validated_by: nil,
      validated_at: nil
    }
    if communication.questions?
      result = Vazivo::AuditScorer.call(self)
      attrs[:score] = result.score if result.score.present?
    end
    transaction do
      update!(attrs)
      record_event!("approval_submitted", {})
    end
    self
  end

  def mark_read!(by: Current.user)
    ensure_not_dependency_blocked!
    ensure_required_answers!
    attrs = { status: "read", completed_at: Time.current, awareness: "done" }
    attrs.merge!(scored_attrs) if communication.questions?
    transaction do
      update!(attrs)
      record_user_read!(by) if by
    end
    self
  end

  # Explicit store acknowledgement is distinct from a per-user read receipt.
  # Locking preserves the first actor and timestamp when requests are retried.
  def acknowledge!(by:)
    unless communication.sent? && communication.acknowledgement_required? &&
           communication.tenant.feature?(:morocco_ops) && by&.tenant_id == communication.tenant_id &&
           by.memberships.exists?(org_unit_id: org_unit_id, role: "store")
      raise ArgumentError, I18n.t("broadcasts.not_allowed")
    end

    with_lock do
      return self if acknowledged_at.present?

      mark_read!(by: by) unless finished?
      record_user_read!(by)
      update!(acknowledged_at: Time.current, acknowledged_by: by)
      record_event!("acknowledged", {}, actor: by)
    end
    self
  end

  # Per-user read receipt (store members). Idempotent: first read wins.
  def record_user_read!(user)
    return if user.blank?

    delivery_reads.find_or_create_by!(user_id: user.id) do |receipt|
      receipt.tenant_id = communication.tenant_id
      receipt.read_at = Time.current
    end
  end

  def read_by?(user)
    return false if user.blank?

    if delivery_reads.loaded?
      delivery_reads.any? { |receipt| receipt.user_id == user.id }
    else
      delivery_reads.exists?(user_id: user.id)
    end
  end

  def store_reader_users
    if org_unit.association(:memberships).loaded?
      org_unit.memberships.select { |m| m.role == "store" }.filter_map(&:user).uniq
    else
      User.joins(:memberships)
          .where(memberships: { org_unit_id: org_unit_id, role: "store" })
          .where(tenant_id: communication.tenant_id)
          .distinct
          .to_a
    end
  end

  def read_receipt_counts
    readers = store_reader_users
    reader_ids = readers.map(&:id)
    total = reader_ids.size
    read = if delivery_reads.loaded?
      delivery_reads.count { |receipt| reader_ids.include?(receipt.user_id) }
    else
      delivery_reads.where(user_id: reader_ids).count
    end
    { total: total, read: read, unread: [ total - read, 0 ].max }
  end

  def apply_score!(actor: Current.user)
    result = Vazivo::AuditScorer.call(self)
    return result if result.score.nil?

    @history_actor = actor
    update!(scored_attrs(result))
    result
  ensure
    @history_actor = nil
  end

  def self.awareness_rollup(deliveries)
    total = deliveries.size
    counts = AWARENESS_STEPS.index_with do |step|
      threshold = AWARENESS_STEPS.index(step)
      deliveries.count { |delivery| (AWARENESS_STEPS.index(delivery.awareness) || -1) >= threshold }
    end
    counts.merge(total: total)
  end

  def awareness_reached?(step)
    current = AWARENESS_STEPS.index(awareness)
    return false if current.nil?

    current >= AWARENESS_STEPS.index(step)
  end

  def next_awareness_step
    return if awareness == "done" || pending_approval? || !pending?

    index = AWARENESS_STEPS.index(awareness)
    AWARENESS_STEPS[(index || -1) + 1]
  end

  def advance_awareness!(step, by: Current.user)
    ensure_not_dependency_blocked!
    step = step.to_s
    raise ArgumentError, I18n.t("morocco.awareness.invalid") unless AWARENESS_STEPS.include?(step)
    raise ArgumentError, I18n.t("morocco.awareness.sequence") unless step == next_awareness_step

    if step == "done"
      communication.task? ? complete! : mark_read!(by: by)
    else
      transaction do
        update!(awareness: step)
        record_user_read!(by) if by && step == "read"
      end
    end
  end

  def dependency_blocked?
    return false if finished?
    return false if dependency_cleared_at.present?
    return false unless communication.depends_on_another?

    parent = blocking_parent_delivery
    parent.nil? || !parent.finished?
  end

  def blocking_parent_delivery
    parent_id = communication.depends_on_communication_id
    return if parent_id.blank?

    Delivery.find_by(communication_id: parent_id, org_unit_id: org_unit_id)
  end

  def dependency_blocked_reason
    return unless dependency_blocked?

    parent = communication.depends_on_communication
    title = parent&.title.presence || I18n.t("morocco.dependency.unknown_parent")
    I18n.t("morocco.dependency.blocked_reason", title: title)
  end

  def clear_dependency_block!(by:)
    @history_actor = by
    update!(dependency_cleared_at: Time.current, dependency_cleared_by: by)
    record_event!("dependency_cleared", {}, actor: by)
  ensure
    @history_actor = nil
  end

  def reassign!(user:, by:)
    @history_actor = by
    update!(assignee: user)
  ensure
    @history_actor = nil
  end

  def apply_verdict!(verdict, note:, by:)
    verdict = verdict.to_s
    raise ArgumentError, I18n.t("morocco.verdict.invalid") unless VERDICTS.include?(verdict)

    if pending_approval?
      decide_approval!(verdict, note: note, by: by)
      return self
    end

    attrs = { verdict: verdict, verdict_note: note.presence, validated_by: by, validated_at: Time.current }
    if verdict == APPROVAL_REJECT_VERDICT
      attrs.merge!(status: "pending", completed_at: nil, awareness: "in_progress")
    end
    @history_actor = by
    update!(attrs)
  ensure
    @history_actor = nil
  end

  def decide_approval!(verdict, note:, by:)
    raise ArgumentError, I18n.t("morocco.approval.not_pending") unless pending_approval?
    raise ArgumentError, I18n.t("morocco.approval.note_required") if note.to_s.strip.blank?

    verdict = verdict.to_s
    raise ArgumentError, I18n.t("morocco.verdict.invalid") unless VERDICTS.include?(verdict)

    attrs = { verdict: verdict, verdict_note: note.to_s.strip, validated_by: by, validated_at: Time.current }
    if verdict == APPROVAL_REJECT_VERDICT
      attrs.merge!(status: "pending", completed_at: nil, awareness: "in_progress")
      event_kind = "approval_rejected"
    else
      attrs.merge!(status: "completed", completed_at: Time.current, awareness: "done")
      if communication.questions? && score.blank?
        result = Vazivo::AuditScorer.call(self)
        attrs[:score] = result.score if result.score.present?
      end
      event_kind = "approval_approved"
    end

    @history_actor = by
    transaction do
      update!(attrs)
      record_event!(event_kind, { verdict: verdict, note: verdict_note }, actor: by)
    end
    self
  ensure
    @history_actor = nil
  end

  def record_proof_event!(actor: Current.user, request_id: nil)
    return unless photo_before.attached? || photo_after.attached? || proof_files.attached? || request_id.present?

    record_event!(
      "proof",
      {
        photo_before: photo_before.attached?,
        photo_after: photo_after.attached?,
        files: proof_files.count,
        request_id: request_id
      },
      actor: actor
    )
  end

  def record_event!(kind, payload = {}, actor: history_actor)
    delivery_events.create!(
      tenant_id: communication.tenant_id,
      kind: kind,
      payload: payload,
      actor: actor,
      created_at: Time.current
    )
  end

  def pending?
    status == "pending"
  end

  def pending_approval?
    status == "pending_approval"
  end

  def answer_for(question)
    delivery_answers.find { |answer| answer.communication_question_id == question.id }
  end

  def save_answers!(raw_answers)
    return if raw_answers.blank?

    questions = communication.communication_questions.index_by(&:id)
    transaction do
      raw_answers.each do |question_id, payload|
        question = questions[question_id.to_i]
        next unless question

        answer = delivery_answers.find_or_initialize_by(communication_question: question)
        if question.image?
          file = extract_uploaded_file(payload)
          answer.image.attach(file) if file.present?
          answer.value = { "attached" => answer.image.attached? }
        else
          answer.value = normalize_answer_value(question, payload)
        end
        answer.save!
      end
    end
  end

  def required_answers_complete?
    communication.communication_questions.none? do |question|
      next false unless question.required?

      answer = answer_for(question)
      answer.nil? || !answer.filled?
    end
  end

  private

  def scored_attrs(result = Vazivo::AuditScorer.call(self))
    return {} if result.score.nil?

    attrs = { score: result.score }
    if verdict.blank? && result.verdict.present?
      attrs.merge!(
        verdict: result.verdict,
        validated_at: Time.current,
        validated_by: history_actor
      )
    end
    attrs
  end

  def history_actor
    @history_actor || Current.user
  end

  def log_history_changes
    if saved_change_to_status?
      record_event!("status", { from: saved_change_to_status[0], to: saved_change_to_status[1] })
    end
    if saved_change_to_awareness?
      record_event!("awareness", { from: saved_change_to_awareness[0], to: saved_change_to_awareness[1] })
    end
    if saved_change_to_assignee_id?
      record_event!("assignee", { from: saved_change_to_assignee_id[0], to: saved_change_to_assignee_id[1] })
    end
    if saved_change_to_verdict?
      record_event!(
        "verdict",
        {
          from: saved_change_to_verdict[0],
          to: saved_change_to_verdict[1],
          note: verdict_note
        }
      )
    end
  end

  def ensure_not_dependency_blocked!
    return unless dependency_blocked?

    raise ArgumentError, dependency_blocked_reason
  end

  def acceptable_proof
    errors.add(:base, I18n.t("task_proof.too_many", count: PROOF_MAX_COUNT)) if proof_files.size > PROOF_MAX_COUNT
    legacy_photos = [ photo_before, photo_after ].select(&:attached?)
    (proof_files.to_a + legacy_photos).each do |attachment|
      allowed = attachment == photo_before || attachment == photo_after ? PROOF_IMAGE_TYPES : PROOF_FILE_TYPES
      if allowed.exclude?(attachment.blob.content_type)
        errors.add(:base, I18n.t("task_proof.invalid_type"))
      end
      if attachment.blob.byte_size > PROOF_MAX_BYTES
        errors.add(:base, I18n.t("task_proof.too_large", size: PROOF_MAX_BYTES / 1.megabyte))
      end
    end
  end

  def ensure_proof!
    return unless communication.requires_proof?
    return if proof_files.attached? || photo_before.attached? && photo_after.attached?

    raise ArgumentError, I18n.t("morocco.proof_required")
  end

  def ensure_required_answers!
    return if required_answers_complete?

    raise ArgumentError, I18n.t("inbox.answers_required")
  end

  def extract_uploaded_file(payload)
    return payload if file_upload?(payload)

    payload = payload.to_unsafe_h if payload.respond_to?(:to_unsafe_h)
    payload = payload.to_h if payload.respond_to?(:to_h)
    return nil unless payload.is_a?(Hash)

    file = payload["image"].presence || payload[:image].presence || payload["file"].presence || payload[:file]
    file_upload?(file) ? file : nil
  end

  def file_upload?(value)
    value.respond_to?(:tempfile) || value.respond_to?(:path) && value.respond_to?(:original_filename)
  end

  def normalize_answer_value(question, payload)
    payload = payload.to_unsafe_h if payload.respond_to?(:to_unsafe_h)
    payload = payload.to_h if payload.respond_to?(:to_h)

    case question.question_type
    when "multi_choice"
      choices = Array(payload.is_a?(Hash) ? (payload["choices"] || payload[:choices]) : payload).map(&:to_s).reject(&:blank?)
      { "choices" => choices }
    else
      text = if payload.is_a?(Hash)
        payload["text"].presence || payload[:text].presence || payload["value"].presence || payload[:value]
      else
        payload
      end
      { "text" => text.to_s }
    end
  end
end
