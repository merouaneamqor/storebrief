class Delivery < ApplicationRecord
  include Vazivo::Execution

  STATUSES = %w[pending completed read].freeze
  AWARENESS_STEPS = %w[received read understood in_progress done].freeze
  VERDICTS = %w[conforme improve non_conforme].freeze

  belongs_to :communication
  belongs_to :org_unit
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :validated_by, class_name: "User", optional: true
  has_many :delivery_answers, dependent: :destroy
  has_many :escalation_events, as: :subject, dependent: :destroy
  has_one_attached :photo_before
  has_one_attached :photo_after

  validates :status, inclusion: { in: STATUSES }
  validates :org_unit_id, uniqueness: { scope: :communication_id }

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
    ensure_required_answers!
    ensure_proof!
    update!(status: "completed", completed_at: Time.current, awareness: "done")
  end

  def mark_read!
    ensure_required_answers!
    update!(status: "read", completed_at: Time.current, awareness: "done")
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
    return if awareness == "done" || !pending?

    index = AWARENESS_STEPS.index(awareness)
    AWARENESS_STEPS[(index || -1) + 1]
  end

  def advance_awareness!(step)
    step = step.to_s
    raise ArgumentError, I18n.t("morocco.awareness.invalid") unless AWARENESS_STEPS.include?(step)
    raise ArgumentError, I18n.t("morocco.awareness.sequence") unless step == next_awareness_step

    if step == "done"
      communication.task? ? complete! : mark_read!
    else
      update!(awareness: step)
    end
  end

  def apply_verdict!(verdict, note:, by:)
    verdict = verdict.to_s
    raise ArgumentError, I18n.t("morocco.verdict.invalid") unless VERDICTS.include?(verdict)

    attrs = { verdict: verdict, verdict_note: note.presence, validated_by: by, validated_at: Time.current }
    if verdict == "non_conforme"
      attrs.merge!(status: "pending", completed_at: nil, awareness: "in_progress")
    end
    update!(attrs)
  end

  def pending?
    status == "pending"
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

  def ensure_proof!
    return unless communication.requires_proof?
    return if photo_before.attached? && photo_after.attached?

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
