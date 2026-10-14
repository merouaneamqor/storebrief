class CorrectiveActionsController < ApplicationController
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_hq_or_area(:verdicts, :escalate) }

  def create
    brief =
      if params[:delivery_id].present?
        spawn_from_delivery!
      elsif params[:checklist_item_response_id].present?
        spawn_from_checklist_item!
      else
        raise ArgumentError, t("morocco.corrective.missing_source")
      end

    redirect_to brief, notice: t("morocco.corrective.created")
  rescue Vazivo::CorrectiveAction::Error, ArgumentError => e
    redirect_back fallback_location: app_root_path, alert: e.message
  end

  private

  def spawn_from_delivery!
    delivery = Delivery.joins(:communication)
                       .where(communications: { tenant_id: tenant_scope.id })
                       .find(params[:delivery_id])
    assert_store_in_scope!(delivery.org_unit_id)
    visit = visit_for(delivery.org_unit_id)

    Vazivo::CorrectiveAction.spawn_from_delivery!(
      delivery: delivery,
      author: current_user,
      visit: visit
    )
  end

  def spawn_from_checklist_item!
    response = ChecklistItemResponse
               .joins(checklist_delivery: :checklist)
               .where(checklists: { tenant_id: tenant_scope.id })
               .find(params[:checklist_item_response_id])
    store_id = response.checklist_delivery.org_unit_id
    assert_store_in_scope!(store_id)
    visit = visit_for(store_id)

    Vazivo::CorrectiveAction.spawn_from_checklist_item!(
      response: response,
      author: current_user,
      visit: visit
    )
  end

  def visit_for(org_unit_id)
    return if params[:visit_id].blank?

    tenant_scope.visits.find_by!(id: params[:visit_id], org_unit_id: org_unit_id)
  end

  def assert_store_in_scope!(org_unit_id)
    return if hq_user?

    allowed = current_user.area_org_unit&.descendant_stores&.exists?(id: org_unit_id)
    raise ArgumentError, t("auth.hq_required") unless allowed
  end
end
