class DeliveryAnswer < ApplicationRecord
  belongs_to :delivery
  belongs_to :communication_question
  has_one_attached :image

  validates :communication_question_id, uniqueness: { scope: :delivery_id }
  validate :question_belongs_to_brief
  validate :value_matches_question

  def text_value
    case value
    when Hash
      value["text"].presence || value[:text]
    when String
      value
    else
      nil
    end
  end

  def list_value
    case value
    when Hash
      Array(value["choices"].presence || value[:choices])
    when Array
      value
    else
      []
    end
  end

  def filled?
    if communication_question.image?
      image.attached?
    elsif communication_question.question_type == "multi_choice"
      list_value.any?(&:present?)
    else
      text_value.present? || list_value.any?(&:present?)
    end
  end

  def display_value(locale: I18n.locale)
    if communication_question.image?
      image.attached? ? image.filename.to_s : ""
    elsif communication_question.question_type == "multi_choice"
      list_value.join(", ")
    else
      text_value.to_s
    end
  end

  private

  def question_belongs_to_brief
    return if delivery.blank? || communication_question.blank?
    return if delivery.communication_id == communication_question.communication_id

    errors.add(:communication_question, :invalid)
  end

  def value_matches_question
    return if communication_question.blank?
    return if filled? || !communication_question.required?

    errors.add(:value, :blank)
  end
end
