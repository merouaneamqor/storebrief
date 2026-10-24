class DeliveryDependenciesController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:briefs) }
  before_action :set_delivery

  def clear
    @delivery.clear_dependency_block!(by: current_user)
    redirect_to @delivery.communication, notice: t("morocco.dependency.cleared")
  end

  def reassign
    user = assignee_for_store
    @delivery.reassign!(user: user, by: current_user)
    redirect_to @delivery.communication, notice: t("morocco.dependency.reassigned")
  rescue ArgumentError => e
    redirect_to @delivery.communication, alert: e.message
  end

  private

  def set_delivery
    @delivery = Delivery.joins(:communication)
                        .where(communications: { tenant_id: tenant_scope.id })
                        .find(params[:delivery_id])
  end

  def assignee_for_store
    user_id = params[:assignee_id].presence
    return nil if user_id.blank?

    user = tenant_scope.users.find(user_id)
    unless @delivery.org_unit.users.exists?(id: user.id)
      raise ArgumentError, t("morocco.dependency.assignee_invalid")
    end

    user
  end
end
