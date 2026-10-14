class ChecklistTemplate < ApplicationRecord
  include Bilingual

  CATEGORIES = %w[opening closing cleanliness safety promotions equipment store_visit].freeze
  ITEM_TYPES = %w[section question].freeze
  KEY_FORMAT = /\A[a-z][a-z0-9_]{0,47}\z/

  belongs_to :tenant

  validates :category, inclusion: { in: CATEGORIES }
  validates :title_fr, presence: true
  validate :question_keys_must_be_unique


  bilingual_fields :title, :description

  def item_defs
    Array(items).map(&:with_indifferent_access)
  end

  # Questions only (skips sections). Legacy flat items count as questions.
  def question_defs
    item_defs.filter_map do |item|
      next if item[:type].to_s == "section"

      item
    end
  end

  def question_count
    question_defs.size
  end

  def self.normalize_items(raw)
    keys_seen = Hash.new(0)
    item_rows(raw).filter_map do |row|
      row = row.to_h.with_indifferent_access
      type = row[:type].to_s.presence || "question"
      type = "question" unless ITEM_TYPES.include?(type)

      title_fr = row[:title_fr].to_s.strip
      next if title_fr.blank?

      key = normalize_key(row[:key], title_fr, type, keys_seen)

      if type == "section"
        {
          "type" => "section",
          "key" => key,
          "title_fr" => title_fr,
          "title_ar" => row[:title_ar].to_s.strip.presence
        }.compact
      else
        photo = row[:requires_photo]
        photo = photo.last if photo.is_a?(Array)
        required = row[:required]
        required = required.last if required.is_a?(Array)

        entry = {
          "type" => "question",
          "key" => key,
          "title_fr" => title_fr,
          "title_ar" => row[:title_ar].to_s.strip.presence,
          "required" => !!ActiveModel::Type::Boolean.new.cast(required),
          "requires_photo" => !!ActiveModel::Type::Boolean.new.cast(photo)
        }
        show_if = normalize_show_if(row[:show_if])
        entry["show_if"] = show_if if show_if
        entry.compact
      end
    end
  end

  def self.item_rows(raw)
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    if raw.is_a?(Hash)
      raw.sort_by { |k, _| k.to_s.to_i }.map(&:last)
    else
      Array(raw)
    end
  end


  def self.normalize_key(raw_key, title_fr, type, keys_seen)
    explicit = raw_key.to_s.strip.downcase.gsub(/[^a-z0-9_]/, "")
    # Keep explicit keys as-is so uniqueness validation can reject duplicates.
    return explicit if explicit.present? && explicit.match?(KEY_FORMAT)

    base = title_fr.to_s.parameterize(separator: "_").presence || type
    base = base.gsub(/[^a-z0-9_]/, "")[0, 40]
    base = type if base.blank? || base !~ /\A[a-z]/
    keys_seen[base] += 1
    keys_seen[base] == 1 ? base : "#{base}_#{keys_seen[base]}"
  end


  def self.normalize_show_if(raw)
    return if raw.blank?

    data = raw.to_h.with_indifferent_access
    question_key = data[:question_key].to_s.strip
    equals = data[:equals].to_s.strip
    return if question_key.blank? || equals.blank?

    { "question_key" => question_key, "equals" => equals }
  end

  private_class_method :normalize_key, :normalize_show_if, :item_rows

  private

  def question_keys_must_be_unique
    keys = question_defs.filter_map { |q| q[:key].to_s.strip.presence }
    return if keys.empty?
    return if keys.size == keys.uniq.size

    errors.add(:items, :duplicate_question_keys)
  end
end
