class KbArticle < ApplicationRecord
  include Bilingual

  PUBLISH_STATES = %w[draft published archived].freeze
  # Empty audience_roles = visible to every role (default). Non-empty = allow-list for #75.
  AUDIENCE_ROLES = Membership::ROLES

  belongs_to :tenant
  belongs_to :kb_category
  belongs_to :author, class_name: "User", optional: true
  has_many :kb_article_versions, dependent: :destroy

  validates :title_fr, presence: true
  validates :body_fr, presence: true
  validates :publish_state, inclusion: { in: PUBLISH_STATES }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validate :category_same_tenant
  validate :audience_roles_allowed

  scope :ordered, -> { order(updated_at: :desc, id: :desc) }
  scope :with_state, ->(state) { where(publish_state: state) if PUBLISH_STATES.include?(state.to_s) }
  scope :published, -> { where(publish_state: "published") }
  scope :drafts, -> { where(publish_state: "draft") }
  scope :archived, -> { where(publish_state: "archived") }
  # Empty audience = all roles. Otherwise the role must be listed.
  scope :visible_to_role, lambda { |role|
    role = role.to_s
    if role.blank? || AUDIENCE_ROLES.exclude?(role)
      all
    else
      where("cardinality(audience_roles) = 0 OR ? = ANY(audience_roles)", role)
    end
  }

  bilingual_fields :title, :body

  before_validation :apply_defaults
  before_validation :normalize_audience_roles
  after_save :refresh_search_vector!

  def draft?
    publish_state == "draft"
  end

  def published?
    publish_state == "published"
  end

  def archived?
    publish_state == "archived"
  end

  def visible_to_role?(role)
    roles = Array(audience_roles).map(&:to_s).reject(&:blank?)
    return true if roles.empty?

    roles.include?(role.to_s)
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

  # Keep FTS vector in sync even when schema.rb load skips the PG trigger.
  def refresh_search_vector!
    self.class.connection.exec_update(
      self.class.sanitize_sql_array([
        <<~SQL.squish,
          UPDATE kb_articles SET search_vector =
            setweight(to_tsvector('simple', coalesce(title_fr, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce(title_ar, '')), 'A') ||
            setweight(to_tsvector('simple', coalesce(body_fr, '')), 'B') ||
            setweight(to_tsvector('simple', coalesce(body_ar, '')), 'B')
          WHERE id = ?
        SQL
        id
      ]),
      "KbArticle RefreshSearchVector"
    )
  end

  private

  def apply_defaults
    self.publish_state = "draft" if publish_state.blank?
    self.version = 1 if version.blank? || version.to_i < 1
    self.body_fr = body_fr.to_s
  end

  def normalize_audience_roles
    self.audience_roles = Array(audience_roles).map(&:to_s).map(&:strip).reject(&:blank?).uniq & AUDIENCE_ROLES
  end

  def audience_roles_allowed
    invalid = Array(audience_roles).map(&:to_s) - AUDIENCE_ROLES
    return if invalid.empty?

    errors.add(:audience_roles, :invalid)
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
