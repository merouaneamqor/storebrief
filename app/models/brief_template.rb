class BriefTemplate < ApplicationRecord
  include Bilingual

  belongs_to :tenant

  validates :name, presence: true
  validates :title_fr, presence: true
  validates :format, inclusion: { in: Communication::FORMATS }
  validates :priority, inclusion: { in: Communication::PRIORITIES }

  bilingual_fields :title, :body

  scope :ordered, -> { order(:name, :id) }

  # Snapshot a brief (questions included) so HQ can redeploy it later.
  def self.capture!(communication, name: nil)
    communication.tenant.brief_templates.create!(
      name: name.presence || communication.title_fr,
      title_fr: communication.title_fr,
      title_ar: communication.title_ar,
      body_fr: communication.body_fr,
      body_ar: communication.body_ar,
      format: communication.format,
      priority: communication.priority,
      requires_proof: communication.requires_proof,
      questions: communication.communication_questions.ordered.map do |question|
        {
          "question_type" => question.question_type,
          "title_fr" => question.title_fr,
          "title_ar" => question.title_ar,
          "required" => question.required,
          "options" => question.options
        }
      end
    )
  end

  def question_defs
    Array(questions).map(&:with_indifferent_access)
  end

  # A fresh draft the HQ can retarget and send from the brief editor.
  def build_communication(author:)
    brief = tenant.communications.new(
      author: author,
      title_fr: title_fr,
      title_ar: title_ar,
      body_fr: body_fr,
      body_ar: body_ar,
      format: format,
      priority: priority,
      requires_proof: requires_proof,
      status: "draft"
    )
    question_defs.each_with_index do |question, index|
      brief.communication_questions.build(
        position: index,
        question_type: question[:question_type],
        title_fr: question[:title_fr],
        title_ar: question[:title_ar],
        required: ActiveModel::Type::Boolean.new.cast(question[:required]),
        options: question[:options]
      )
    end
    brief
  end
end
