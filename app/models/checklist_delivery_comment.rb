class ChecklistDeliveryComment < ApplicationRecord
  belongs_to :tenant
  belongs_to :checklist_delivery
  belongs_to :user
  belongs_to :parent, class_name: "ChecklistDeliveryComment", optional: true
  has_many :replies, class_name: "ChecklistDeliveryComment", foreign_key: :parent_id,
    inverse_of: :parent, dependent: :restrict_with_exception
  validates :body, presence: true, length: { maximum: 4_000 }
  validate :boundaries
  before_validation :resolve_mentions, on: :create
  after_create :record_history
  after_create_commit :notify_mentions

  def readonly?
    persisted?
  end

  def self.can_read?(user, delivery)
    user.tenant_id == delivery.checklist.tenant_id &&
      (user.allows?(:monitor, org_unit: delivery.org_unit) || user.allows?(:execute, org_unit: delivery.org_unit))
  end

  private

  def boundaries
    return errors.add(:checklist_delivery, :invalid) unless checklist_delivery && tenant_id == checklist_delivery.checklist.tenant_id

    errors.add(:user, :invalid) unless user && self.class.can_read?(user, checklist_delivery)
    if parent && (parent.checklist_delivery_id != checklist_delivery_id || parent.tenant_id != tenant_id)
      errors.add(:parent, :invalid)
    end
  end

  def resolve_mentions
    return unless checklist_delivery && tenant

    candidates = tenant.users.select { |candidate| self.class.can_read?(candidate, checklist_delivery) }
    tokens = DeliveryComment.parse_mention_tokens(body).map(&:downcase)
    explicit = Array(mentioned_user_ids).map(&:to_i)
    self.mentioned_user_ids = candidates.select do |candidate|
      candidate.id != user_id && (explicit.include?(candidate.id) ||
        tokens.intersect?([ candidate.email.downcase, candidate.email.split("@", 2).first.downcase, candidate.name.downcase ]))
    end.map(&:id)
  end

  def record_history
    checklist_delivery.record_review_event!("comment", { comment_id: id, parent_id: parent_id, mentioned_user_ids: mentioned_user_ids }, actor: user)
  end

  def notify_mentions
    return unless tenant.feature?(:push_alerts) && WebPushConfig.configured?

    tenant.users.where(id: mentioned_user_ids).each do |recipient|
      next unless self.class.can_read?(recipient, checklist_delivery)

      url = recipient.store? && !recipient.hq? && !recipient.area? ? "/checklists/deliveries/#{checklist_delivery_id}" : "/checklist_reviews/#{checklist_delivery_id}"
      PushNotifier.deliver_to_user!(user: recipient, tenant: tenant, notifiable: self,
        title: checklist_delivery.checklist.title, body: body.truncate(160), url: url)
    end
  end
end
