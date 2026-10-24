module FeedEntry
  extend ActiveSupport::Concern

  included do
    belongs_to :tenant
    belongs_to :user
    belongs_to :subject, polymorphic: true
    validates :subject_type, inclusion: { in: %w[Delivery FeedPost] }
    validate :accessible_subject
  end

  private

  def accessible_subject
    return errors.add(:base, :invalid) unless user && subject && user.tenant_id == tenant_id

    valid = case subject
    when Delivery
      communication = subject.communication
      communication.tenant_id == tenant_id && communication.sent? &&
        Vazivo::Newsfeed::FORMATS.include?(communication.format)
    when FeedPost
      subject.tenant_id == tenant_id && subject.status == "published"
    else
      false
    end
    valid &&= user.hq? || (!user.area? && user.memberships.exists?(org_unit_id: subject.org_unit_id, role: "store"))
    errors.add(:base, :invalid) unless valid
  end
end
