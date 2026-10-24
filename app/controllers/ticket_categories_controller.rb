class TicketCategoriesController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action :require_hq
  before_action do
    redirect_to app_root_path, alert: t("auth.hq_required") unless user_allows?(:manage_org, tenant_wide: true)
  end

  def create
    category = TicketCategory.new(params.require(:ticket_category).permit(:name, :department, :sla_hours).merge(tenant: tenant_scope))
    flash[:alert] = category.errors.full_messages.to_sentence unless category.save
    redirect_to incident_tickets_path, status: :see_other
  end

  def update
    category = TicketCategory.where(tenant: tenant_scope).find(params[:id])
    unless category.update(params.require(:ticket_category).permit(:department, :sla_hours))
      flash[:alert] = category.errors.full_messages.to_sentence
    end
    redirect_to incident_tickets_path, status: :see_other
  end
end
