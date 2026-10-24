module Vazivo
  # Scores a delivery from its answers and maps the percent to a verdict.
  # Choices with correct flags, yes/no and ratings earn weighted credit.
  # Other forms use weighted completion. N/A never contributes to the denominator.
  class AuditScorer
    CONFORME_MIN = 80
    IMPROVE_MIN = 50

    Result = Struct.new(:score, :verdict, :earned, :possible, keyword_init: true)

    def self.call(delivery)
      new(delivery).call
    end

    def self.verdict_for(score)
      return if score.nil?

      if score >= CONFORME_MIN
        "conforme"
      elsif score >= IMPROVE_MIN
        "improve"
      else
        "non_conforme"
      end
    end

    def initialize(delivery)
      @delivery = delivery
      @questions = delivery.communication.communication_questions.ordered.to_a
      @answers = delivery.delivery_answers.includes(:communication_question).index_by(&:communication_question_id)
    end

    def call
      return Result.new(score: nil, verdict: nil, earned: 0, possible: 0) if @questions.empty?

      questions = scorable_questions.presence || @questions
      # N/A is an explicit exclusion, including in completion-only forms.
      questions = questions.reject { |q| q.question_type == "yes_no_na" && @answers[q.id]&.text_value == "na" }
      possible = questions.sum(&:weight)
      earned = questions.sum do |question|
        answer = @answers[question.id]
        credit = if question.question_type == "yes_no_na"
          answer&.text_value == "yes" ? 1 : 0
        elsif question.question_type == "rating"
          TypedFormValue.valid?("rating", answer&.text_value) ? answer.text_value.to_i / 5.0 : 0
        elsif question.choice? && correct_labels(question).any?
          answer_correct?(question) ? 1 : 0
        else
          answer&.filled? ? 1 : 0
        end
        question.weight * credit
      end
      percent = possible.zero? ? nil : ((earned.to_f / possible) * 100).round
      Result.new(score: percent, verdict: self.class.verdict_for(percent), earned: earned, possible: possible)
    end

    private

    def scorable_questions
      @questions.select do |question|
        %w[yes_no_na rating].include?(question.question_type) || (question.choice? && correct_labels(question).any?)
      end
    end

    def answer_correct?(question)
      answer = @answers[question.id]
      return false unless answer&.filled?

      expected = correct_labels(question).map(&:to_s).sort
      actual =
        if question.question_type == "multi_choice"
          answer.list_value.map(&:to_s).reject(&:blank?).sort
        else
          [ answer.text_value.to_s.presence || answer.list_value.first.to_s ].reject(&:blank?).sort
        end
      expected == actual
    end

    def correct_labels(question)
      Array(question.options).filter_map do |option|
        next unless option["correct"] == true || option[:correct] == true

        option["label_fr"].presence || option[:label_fr]
      end
    end
  end
end
