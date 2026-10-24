# Shared wire values keep localized labels separate from stored answers.
module TypedFormValue
  TYPES = %w[number date rating yes_no_na].freeze
  YES_NO_NA = %w[yes no na].freeze

  def self.valid?(type, value)
    case type
    when "number"
      value.to_s.match?(/\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)\z/) && BigDecimal(value.to_s).finite?
    when "date"
      value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value.to_s).year.positive?
    when "rating"
      %w[1 2 3 4 5].include?(value.to_s)
    when "yes_no_na"
      YES_NO_NA.include?(value.to_s)
    else
      true
    end
  rescue ArgumentError
    false
  end
end
