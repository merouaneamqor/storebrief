class AuditTemplate < ApplicationRecord
  include Bilingual

  KINDS = %w[verdict yes_no text].freeze

  belongs_to :tenant
  has_many :visits, dependent: :nullify

  validates :title_fr, presence: true
  validate :sections_are_valid

  bilingual_fields :title, :description

  def questions
    sections_data.flat_map { |section| Array(section["questions"]) }
  end

  def sections_data
    Array(sections).map { |section| section.to_h.stringify_keys }
  end

  def form_sections
    data = sections_data
    return [ self.class.blank_section ] if data.empty?

    data.map do |section|
      questions = Array(section["questions"]).map { |question| self.class.form_question(question) }
      questions = [ self.class.blank_question ] if questions.empty?
      {
        "key" => section["key"],
        "title_fr" => section["title_fr"].to_s,
        "title_ar" => section["title_ar"].to_s,
        "questions" => questions
      }
    end
  end

  def question_visible?(question, answers)
    key = question["show_if_key"].presence
    return true if key.blank?

    answers.to_h.stringify_keys[key].to_s == question["show_if_value"].to_s
  end

  def max_points
    questions.sum { |question| question["points"].to_i }
  end

  def self.normalize_sections(raw)
    list = ordered_list(raw)

    list.filter_map.with_index do |section, index|
      section = section.to_h.with_indifferent_access
      questions = normalize_questions(section[:questions])
      next if section[:title_fr].to_s.strip.blank? && questions.empty?

      {
        "key" => safe_key(section[:key], "s#{index + 1}"),
        "title_fr" => section[:title_fr].to_s.strip,
        "title_ar" => section[:title_ar].to_s.strip.presence,
        "questions" => questions
      }
    end
  end

  def self.blank_section
    { "key" => "s1", "title_fr" => "", "title_ar" => "", "questions" => [ blank_question ] }
  end

  def self.blank_question
    form_question({})
  end

  def self.form_question(question)
    question = question.to_h.stringify_keys
    {
      "key" => question["key"].presence || "q1",
      "prompt_fr" => question["prompt_fr"].to_s,
      "prompt_ar" => question["prompt_ar"].to_s,
      "required" => question.fetch("required", true),
      "kind" => KINDS.include?(question["kind"]) ? question["kind"] : "verdict",
      "points" => question["points"].to_i,
      "show_if_key" => question["show_if_key"].to_s,
      "show_if_value" => question["show_if_value"].to_s
    }
  end

  def self.normalize_questions(raw)
    list = ordered_list(raw)

    list.filter_map.with_index do |question, index|
      question = question.to_h.with_indifferent_access
      next if question[:prompt_fr].to_s.strip.blank?

      {
        "key" => safe_key(question[:key], "q#{index + 1}"),
        "prompt_fr" => question[:prompt_fr].to_s.strip,
        "prompt_ar" => question[:prompt_ar].to_s.strip.presence,
        "required" => ActiveModel::Type::Boolean.new.cast(question[:required]),
        "kind" => KINDS.include?(question[:kind].to_s) ? question[:kind].to_s : "verdict",
        "points" => question[:points].to_i.clamp(0, 100),
        "show_if_key" => question[:show_if_key].to_s.strip.presence,
        "show_if_value" => question[:show_if_value].to_s.strip.presence
      }
    end
  end

  def self.ordered_list(raw)
    case raw
    when Array
      raw
    when ActionController::Parameters
      raw.to_unsafe_h.sort_by { |key, _| key.to_s.to_i }.map(&:last)
    when Hash
      raw.sort_by { |key, _| key.to_s.to_i }.map(&:last)
    else
      []
    end
  end

  def self.safe_key(value, fallback)
    key = value.to_s.strip
    return fallback unless key.match?(/\A[a-z][a-z0-9_]{0,20}\z/)

    key
  end

  private

  def sections_are_valid
    data = sections_data
    if data.empty?
      errors.add(:sections, :blank)
      return
    end

    keys = []
    data.each do |section|
      errors.add(:sections, :invalid) if section["title_fr"].blank?
      Array(section["questions"]).each do |question|
        errors.add(:sections, :invalid) if question["prompt_fr"].blank?
        errors.add(:sections, :invalid) unless KINDS.include?(question["kind"])
        keys << question["key"]
      end
    end
    errors.add(:sections, :invalid) unless keys.uniq.size == keys.size

    known = keys.compact
    questions.each do |question|
      dependency = question["show_if_key"]
      next if dependency.blank?
      next if dependency != question["key"] && known.include?(dependency) && question["show_if_value"].present?

      errors.add(:sections, :invalid)
    end
  end
end
