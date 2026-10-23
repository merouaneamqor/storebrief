class CommunicationQuestion < ApplicationRecord
  include Bilingual

  TYPES = %w[short_text long_text single_choice multi_choice dropdown image signature number date rating yes_no_na].freeze
  CHOICE_TYPES = %w[single_choice multi_choice dropdown].freeze

  belongs_to :communication
  has_many :delivery_answers, dependent: :destroy

  validates :title_fr, presence: true
  validates :question_type, inclusion: { in: TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :weight, numericality: { greater_than: 0, less_than: 1_000_000 }
  validate :signature_feature
  validate :options_shape
  validate :communication_is_draft, on: %i[create update]

  before_destroy :ensure_communication_is_draft

  bilingual_fields :title

  scope :ordered, -> { order(:position, :id) }

  def options=(value)
    parsed = case value
    when String
      value.blank? ? [] : JSON.parse(value)
    when Array
      value
    else
      []
    end
    super(Array(parsed).map { |option| normalize_option(option) })
  rescue JSON::ParserError
    super([])
  end

  def choice?
    CHOICE_TYPES.include?(question_type)
  end

  def image?
    %w[image signature].include?(question_type)
  end

  def option_labels(locale: I18n.locale)
    Array(options).filter_map do |option|
      next if option.blank?

      fr = option["label_fr"].presence || option[:label_fr]
      ar = option["label_ar"].presence || option[:label_ar]
      locale.to_s == "ar" && ar.present? ? ar : fr
    end
  end

  private

  def signature_feature
    errors.add(:question_type, :invalid) if question_type == "signature" && !communication&.tenant&.feature?(:morocco_ops)
  end

  def normalize_option(option)
    option = option.to_unsafe_h if option.respond_to?(:to_unsafe_h)
    option = option.to_h if option.respond_to?(:to_h)
    {
      "label_fr" => option["label_fr"].presence || option[:label_fr].to_s,
      "label_ar" => option["label_ar"].presence || option[:label_ar].to_s,
      "correct" => option["correct"] == true || option[:correct] == true
    }.tap { |normalized| normalized.delete("correct") unless normalized["correct"] }
  end

  def options_shape
    list = Array(options)
    if choice?
      valid = list.any? { |option| option["label_fr"].present? }
      errors.add(:options, :blank) unless valid
    else
      self.options = [] if options.present?
    end
  end

  def communication_is_draft
    return if communication.blank? || communication.draft?

    errors.add(:base, :frozen)
  end

  def ensure_communication_is_draft
    return if communication.blank? || communication.draft?

    errors.add(:base, :frozen)
    throw :abort
  end
end
