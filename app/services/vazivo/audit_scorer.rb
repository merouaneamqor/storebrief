module Vazivo
  # Scores a delivery from its answers and maps the percent to a verdict.
  # Choice options may mark `"correct": true`. Without correct flags, the score
  # is the share of answered questions (completion fallback).
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

      if scorable_choice_questions.any?
        score_choice_questions
      else
        score_completion
      end
    end

    private

    def scorable_choice_questions
      @scorable_choice_questions ||= @questions.select { |question| question.choice? && correct_labels(question).any? }
    end

    def score_choice_questions
      earned = 0
      possible = scorable_choice_questions.size
      scorable_choice_questions.each do |question|
        earned += 1 if answer_correct?(question)
      end
      percent = ((earned.to_f / possible) * 100).round
      Result.new(score: percent, verdict: self.class.verdict_for(percent), earned: earned, possible: possible)
    end

    def score_completion
      possible = @questions.size
      earned = @questions.count { |question| @answers[question.id]&.filled? }
      percent = possible.zero? ? nil : ((earned.to_f / possible) * 100).round
      Result.new(score: percent, verdict: self.class.verdict_for(percent), earned: earned, possible: possible)
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
