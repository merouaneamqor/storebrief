class DeliveryComment < ApplicationRecord
  # Mentions: @email, @local-part, or @"Full Name"
  MENTION_PATTERN = /@(?:"([^"]+)"|([^\s@]+))/

  belongs_to :tenant
  belongs_to :delivery
  belongs_to :user
  belongs_to :parent, class_name: "DeliveryComment", optional: true
  has_many :replies, class_name: "DeliveryComment", foreign_key: :parent_id,
                     inverse_of: :parent, dependent: :restrict_with_exception

  validates :body, presence: true, length: { maximum: 4_000 }
  validate :parent_belongs_to_same_delivery
  validate :tenant_matches_delivery

  before_validation :assign_tenant_from_delivery, on: :create
  before_validation :resolve_mentions, on: :create
  after_create :record_audit_event!
  after_create :notify_mentions!

  scope :roots, -> { where(parent_id: nil) }
  scope :chronological, -> { order(:created_at, :id) }

  # Append-only audit trail: never update or destroy once persisted.
  def readonly?
    persisted?
  end

  def mentioned_users
    ids = Array(mentioned_user_ids).map(&:to_i).uniq
    return User.none if ids.empty?

    User.where(tenant_id: tenant_id, id: ids)
  end

  def self.parse_mention_tokens(body)
    body.to_s.scan(MENTION_PATTERN).flatten.compact.map(&:strip).reject(&:blank?).uniq
  end

  private

  def assign_tenant_from_delivery
    self.tenant_id ||= delivery&.communication&.tenant_id
  end

  def resolve_mentions
    tokens = self.class.parse_mention_tokens(body)
    explicit = Array(mentioned_user_ids).map(&:to_i)
    resolved = explicit

    if tokens.any? && delivery
      candidates = mentionable_users
      tokens.each do |token|
        match = find_mention_match(candidates, token)
        resolved << match.id if match
      end
    end

    self.mentioned_user_ids = resolved.uniq.reject { |id| id == user_id || id <= 0 }
  end

  def mentionable_users
    tenant.users.includes(:memberships)
  end

  def find_mention_match(candidates, token)
    needle = token.to_s.downcase
    candidates.find do |candidate|
      candidate.email.to_s.downcase == needle ||
        candidate.email.to_s.split("@", 2).first.downcase == needle ||
        candidate.name.to_s.downcase == needle
    end
  end

  def parent_belongs_to_same_delivery
    return if parent.blank?
    return if parent.delivery_id == delivery_id && parent.tenant_id == tenant_id

    errors.add(:parent, :invalid)
  end

  def tenant_matches_delivery
    return if delivery.blank? || tenant_id.blank?

    expected = delivery.communication&.tenant_id
    return if expected.blank? || expected == tenant_id

    errors.add(:tenant, :invalid)
  end

  def record_audit_event!
    delivery.record_event!(
      "comment",
      {
        comment_id: id,
        parent_id: parent_id,
        body_preview: body.to_s.truncate(120),
        mentioned_user_ids: mentioned_user_ids
      },
      actor: user
    )
  end

  def notify_mentions!
    return if mentioned_user_ids.blank?

    NotificationDispatcher.notify_comment_mentions!(self)
  end
end
