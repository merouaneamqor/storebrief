class PlaybookDeployRequestsController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:checklists) }
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_approver, only: %i[approve reject]
  before_action :set_request, only: %i[approve reject]

  def index
    @requests = tenant_scope.playbook_deploy_requests
                            .includes(:playbook, :author, :reviewed_by, :approval_events)
                            .newest_first.limit(50)
  end

  def approve
    decide("approved") do |request|
      deployed = Vazivo::PlaybookDeployer.deploy!(**request.deploy_arguments, request: request)
      request.update!(deployed_at: Time.current, communication: deployed)
      Vazivo::Approval.record!(request, "deployed", current_user)
    end
  end

  def reject
    decide("rejected")
  end

  private

  def require_approver
    return if user_allows?(:approve)

    redirect_to app_root_path, alert: t("approval.errors.not_allowed")
  end

  def set_request
    @request = tenant_scope.playbook_deploy_requests.find(params[:id])
  end

  def decide(decision, &)
    Vazivo::Approval.decide!(@request, approver: current_user, decision: decision,
                                       note: params[:review_note], &)
    redirect_to playbook_deploy_requests_path, notice: t("approval.#{decision}")
  rescue ArgumentError => e
    redirect_to playbook_deploy_requests_path, alert: e.message
  end
end
