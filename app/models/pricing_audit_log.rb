# Append-only record of sensitive commercial changes.
class PricingAuditLog < ApplicationRecord
  belongs_to :user, optional: true

  before_update { raise ActiveRecord::ReadOnlyRecord }
  before_destroy { raise ActiveRecord::ReadOnlyRecord }

  def self.record!(user, action, subject, changes)
    create!(user: user, action: action, subject_type: subject.class.name, subject_id: subject.id,
            changes_made: changes)
  end
end
