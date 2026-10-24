class CommunicationTemplate < ApplicationRecord
  include Bilingual

  belongs_to :tenant
  has_many :communications, dependent: :nullify

  validates :title_fr, presence: true
  validate :question_weights

  validates :body_fr, presence: true, unless: :questions_present?
  validates :format, inclusion: { in: Communication::FORMATS }
  validates :priority, inclusion: { in: Communication::PRIORITIES }

  bilingual_fields :title, :body

  before_validation :apply_priority_default

  def question_defs
    Array(questions).map(&:with_indifferent_access)
  end

  def question_count
    question_defs.size
  end

  def self.normalize_questions(raw)
    question_rows(raw).filter_map.with_index do |row, index|
      row = row.to_h.with_indifferent_access
      title_fr = row[:title_fr].to_s.strip
      next if title_fr.blank?

      question_type = row[:question_type].to_s.strip
      question_type = "short_text" unless CommunicationQuestion::TYPES.include?(question_type)

      required = row[:required]
      required = required.last if required.is_a?(Array)

      {
        "position" => row[:position].presence&.to_i || index,
        "question_type" => question_type,
        "weight" => row[:weight].presence || 1,
        "title_fr" => title_fr,
        "title_ar" => row[:title_ar].to_s.strip.presence,
        "required" => !!ActiveModel::Type::Boolean.new.cast(required),
        "options" => normalize_options(row[:options], question_type)
      }.compact
    end
  end

  def self.from_communication(communication)
    communication.tenant.communication_templates.new(
      title_fr: communication.title_fr,
      title_ar: communication.title_ar,
      body_fr: communication.body_fr.to_s,
      body_ar: communication.body_ar,
      format: communication.format,
      requires_proof: communication.requires_proof,
      requires_approval: communication.requires_approval,
      priority: communication.priority,
      questions: communication.communication_questions.map do |question|
        {
          "position" => question.position,
          "question_type" => question.question_type,
          "weight" => question.weight,
          "title_fr" => question.title_fr,
          "title_ar" => question.title_ar,
          "required" => question.required,
          "options" => Array(question.options)
        }.compact
      end
    )
  end

  def self.question_rows(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    if raw.is_a?(Hash)
      raw.sort_by { |k, _| k.to_s.to_i }.map(&:last)
    else
      Array(raw)
    end
  end

  def self.normalize_options(raw, question_type)
    return [] unless CommunicationQuestion::CHOICE_TYPES.include?(question_type)

    rows = question_rows(raw)
    rows.filter_map do |option|
      option = option.to_h.with_indifferent_access if option.respond_to?(:to_h)
      next if option.blank?

      label_fr = option[:label_fr].to_s.strip
      next if label_fr.blank?

      {
        "correct" => option[:correct] == true,
        "label_fr" => label_fr,
        "label_ar" => option[:label_ar].to_s.strip.presence
      }.compact
    end
  end

  private_class_method :question_rows, :normalize_options

  private

  def question_weights
    question_defs.each do |question|
      weight = question[:weight].presence || 1
      errors.add(:questions, :invalid) unless weight.to_s.match?(/\A\d+(?:\.\d{1,2})?\z/) && weight.to_d.positive? && weight.to_d < 1_000_000
    end
  end

  def apply_priority_default
    self.priority = Communication::DEFAULT_PRIORITY if priority.blank? || format != "task"
  end

  def questions_present?
    question_defs.any? { |question| question[:title_fr].to_s.present? }
  end
end
