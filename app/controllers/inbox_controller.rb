class InboxController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action :require_store_or_assignment_access, except: :index

  def index
    @scope = Vazivo::MyTasks::SCOPES.include?(params[:scope].to_s) ? params[:scope].to_s : Vazivo::MyTasks::DEFAULT_SCOPE
    result = Vazivo::MyTasks.for(user: current_user, tenant: tenant_scope, scope: @scope)
    @deliveries = result.deliveries
    @counts = result.counts
    @store = current_user.store_org_unit
    @multi_store = @deliveries.map(&:org_unit_id).uniq.size > 1
  end

  def show
    @delivery = load_delivery
    @communication = @delivery.communication
    @questions = @communication.communication_questions
    @answers = @delivery.delivery_answers.index_by(&:communication_question_id)
    @store = @delivery.org_unit
  end

  def advance
    @delivery = load_delivery
    return unless deny_without_write_access(@delivery)

    attach_proof(@delivery)
    if params[:step].to_s == "done" && @delivery.communication.questions?
      @delivery.save_answers!(params[:answers])
    end
    @delivery.advance_awareness!(params[:step])
    redirect_to inbox_path(@delivery), notice: t("morocco.awareness.saved")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ArgumentError) ? e.message : t("inbox.answers_required")
    redirect_to inbox_path(@delivery), alert: message
  end

  def complete
    @delivery = load_delivery
    return unless deny_without_write_access(@delivery)

    attach_proof(@delivery)

    begin
      @delivery.save_answers!(params[:answers]) if @delivery.communication.questions?
      if @delivery.communication.task?
        @delivery.complete!
        redirect_to inbox_path(@delivery), notice: t("inbox.task_done")
      else
        @delivery.mark_read!
        redirect_to inbox_path(@delivery), notice: t("inbox.marked_read")
      end
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      message = e.is_a?(ArgumentError) ? e.message : t("inbox.answers_required")
      redirect_to inbox_path(@delivery), alert: message
    end
  end

  private

  def attach_proof(delivery)
    delivery.photo_before.attach(params[:photo_before]) if params[:photo_before].present?
    delivery.photo_after.attach(params[:photo_after]) if params[:photo_after].present?
  end

  def load_delivery
    Delivery.joins(:communication)
            .where(communications: { tenant_id: tenant_scope.id })
            .where("deliveries.org_unit_id IN (:store_ids) OR deliveries.assignee_id = :user_id",
                   store_ids: accessible_store_ids, user_id: current_user.id)
            .includes(:communication, { delivery_answers: { image_attachment: :blob } }, communication: :communication_questions)
            .find(params[:id])
  end

  def accessible_store_ids
    ids = current_user.manageable_store_ids
    ids.empty? ? [ 0 ] : ids
  end

  def require_store_or_assignment_access
    return if current_user.store_org_unit
    return if current_user.manageable_store_ids.any?
    return if assigned_in_tenant?

    redirect_to app_root_path, alert: t("errors.no_store")
  end

  def assigned_in_tenant?
    Delivery.joins(:communication)
            .where(communications: { tenant_id: tenant_scope.id }, assignee_id: current_user.id)
            .exists?
  end

  # Only direct owners (the store manager on that store, HQ, or the assignee)
  # can advance a task. Area managers can see the task but not punch it through.
  def deny_without_write_access(delivery)
    return true if can_write?(delivery)

    redirect_to inbox_path(delivery), alert: t("errors.not_assignable")
    false
  end

  def can_write?(delivery)
    return true if delivery.assignee_id == current_user.id
    return true if current_user.hq? || current_user.super_admin?

    current_user.memberships.where(org_unit_id: delivery.org_unit_id, role: "store").exists?
  end
end
