# A playbook deploy waiting for HQ approval. Nothing is created for stores until approved.
class PlaybookDeployRequest < ApplicationRecord
  include Reviewable

  belongs_to :tenant
  belongs_to :playbook
  belongs_to :author, class_name: "User"
  belongs_to :communication, optional: true

  validates :review_status, presence: true

  scope :newest_first, -> { order(created_at: :desc) }

  def deployed?
    deployed_at.present?
  end

  # Arguments for Vazivo::PlaybookDeployer.deploy! (dates stored as ISO strings).
  def deploy_arguments
    params = deploy_params.with_indifferent_access
    {
      playbook: playbook,
      author: author,
      campaign_on: Date.iso8601(params[:campaign_on]),
      starts_on: params[:starts_on].presence && Date.iso8601(params[:starts_on]),
      org_unit_ids: Array(params[:org_unit_ids]),
      brief_fr: params[:brief_fr],
      brief_ar: params[:brief_ar]
    }
  end
end
