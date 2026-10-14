class KbArticleVersion < ApplicationRecord
  include Bilingual

  belongs_to :kb_article
  belongs_to :author, class_name: "User", optional: true

  validates :version, presence: true, uniqueness: { scope: :kb_article_id },
                      numericality: { only_integer: true, greater_than: 0 }
  validates :title_fr, :body_fr, :publish_state, presence: true

  bilingual_fields :title, :body

  scope :newest_first, -> { order(version: :desc) }
end
