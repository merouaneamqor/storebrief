class OfflineWorkspacesController < ApplicationController
  before_action -> { require_feature!(:briefs) }

  def show
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Vazivo-Offline-Owner"] = "#{current_tenant.id}:#{current_user.id}"
    response.headers["X-Vazivo-Offline-Session"] = offline_session_id
    render json: { owner: "#{current_tenant.id}:#{current_user.id}", csrf_token: form_authenticity_token }
  end
end
