class Delivery < ApplicationRecord
  STATUSES = %w[pending completed read].freeze

  belongs_to :communication
  belongs_to :org_unit
  has_many :delivery_answers, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }
  validates :org_unit_id, uniqueness: { scope: :communication_id }

  scope :pending, -> { where(status: "pending") }
  scope :for_store, ->(org_unit) { where(org_unit_id: org_unit.id) }

  def complete!
    ensure_required_answers!
    update!(status: "completed", completed_at: Time.current)
  end

  def mark_read!
    ensure_required_answers!
    update!(status: "read", completed_at: Time.current)
  end

  def pending?
    status == "pending"
  end

  def answer_for(question)
    delivery_answers.find { |answer| answer.communication_question_id == question.id }
  end

  def save_answers!(raw_answers)
    payload_map = if raw_answers.respond_to?(:to_unsafe_h)
      raw_answers.to_unsafe_h
    else
      raw_answers.to_h
    end
    questions = communication.communication_questions.index_by(&:id)
    transaction do
      payload_map.each do |question_id, payload|
        question = questions[question_id.to_i]
        next unless question

        answer = delivery_answers.find_or_initialize_by(communication_question: question)
        answer.value = normalize_answer_value(question, payload)
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

  def ensure_required_answers!
    return if required_answers_complete?

    raise ArgumentError, I18n.t("inbox.answers_required")
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
