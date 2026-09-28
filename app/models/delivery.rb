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
