class PushSubscriptionsController < ApplicationController
  skip_before_action :require_login, only: :vapid_public_key

  def vapid_public_key
    if WebPushConfig.configured?
      render json: { publicKey: WebPushConfig.public_key }
    else
      render json: { publicKey: nil }, status: :service_unavailable
    end
  end

  def create
    unless WebPushConfig.configured?
      return render json: { error: "push_not_configured" }, status: :service_unavailable
    end

    endpoint = params.require(:endpoint)
    keys = params.require(:keys)
    p256dh = keys.require(:p256dh)
    auth = keys.require(:auth)

    subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: endpoint)
    subscription.assign_attributes(
      tenant: current_user.tenant,
      p256dh: p256dh,
      auth: auth,
      user_agent: request.user_agent.to_s.truncate(255)
    )
    subscription.save!

    render json: { ok: true }, status: :created
  end

  def destroy
    endpoint = params[:endpoint].presence || params.dig(:push_subscription, :endpoint)
    scope = current_user.push_subscriptions
    if endpoint.present?
      scope.where(endpoint: endpoint).destroy_all
    else
      scope.destroy_all
    end

    head :no_content
  end
end
