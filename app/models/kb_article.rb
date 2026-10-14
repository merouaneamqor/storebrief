class KbArticle < ApplicationRecord
  include Bilingual

  PUBLISH_STATES = %w[draft published archived].freeze

  belongs_to :tenant
  belongs_to :kb_category
  belongs_to :author, class_name: "User", optional: true
  has_many :kb_article_versions, dependent: :destroy

  validates :title_fr, presence: true
  validates :body_fr, presence: true
  validates :publish_state, inclusion: { in: PUBLISH_STATES }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validate :category_same_tenant

  scope :ordered, -> { order(updated_at: :desc, id: :desc) }
  scope :with_state, ->(state) { where(publish_state: state) if PUBLISH_STATES.include?(state.to_s) }
  scope :published, -> { where(publish_state: "published") }
  scope :drafts, -> { where(publish_state: "draft") }
  scope :archived, -> { where(publish_state: "archived") }

  bilingual_fields :title, :body

  before_validation :apply_defaults

  def draft?
    publish_state == "draft"
  end

  def published?
    publish_state == "published"
  end

  def archived?
    publish_state == "archived"
  end

  def publish!(by: nil)
    transaction do
      bump_version_if_needed!
      self.publish_state = "published"
      self.published_at ||= Time.current
      self.author = by if by.present?
      save!
      snapshot_version!(by: by)
    end
    self
  end

  def archive!
    update!(publish_state: "archived")
    self
  end

  def unpublish!
    update!(publish_state: "draft")
    self
  end

  private

  def apply_defaults
    self.publish_state = "draft" if publish_state.blank?
    self.version = 1 if version.blank? || version.to_i < 1
    self.body_fr = body_fr.to_s
  end

  def category_same_tenant
    return if kb_category.blank?
    return if kb_category.tenant_id == tenant_id

    errors.add(:kb_category, :invalid)
  end

  def bump_version_if_needed!
    last = kb_article_versions.order(:version).last
    return if last.blank?

    changed_content = last.title_fr != title_fr ||
                      last.title_ar.to_s != title_ar.to_s ||
                      last.body_fr.to_s != body_fr.to_s ||
                      last.body_ar.to_s != body_ar.to_s

    self.version = last.version + 1 if changed_content || last.version >= version
  end

  def snapshot_version!(by: nil)
    return if kb_article_versions.exists?(version: version)

    kb_article_versions.create!(
      version: version,
      title_fr: title_fr,
      title_ar: title_ar,
      body_fr: body_fr,
      body_ar: body_ar,
      publish_state: publish_state,
      published_at: published_at,
      author: by || author
    )
  end
end
