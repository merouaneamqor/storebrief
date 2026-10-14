class InboxController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action :set_store

  def index
    @deliveries = Delivery.current_instances
                          .where(org_unit: @store, communications: { tenant_id: tenant_scope.id, status: "sent" })
                          .includes(communication: :depends_on_communication)
                          .merge(Communication.by_priority)
                          .order("communications.created_at DESC")
    priority = params[:priority].to_s
    @deliveries = @deliveries.where(communications: { priority: priority }) if Communication::PRIORITIES.include?(priority)
  end

  def show
    @delivery = find_delivery
    @communication = @delivery.communication
    @questions = @communication.communication_questions
    @answers = @delivery.delivery_answers.index_by(&:communication_question_id)
    if tenant_feature?(:morocco_ops)
      @mentionable_users = tenant_scope.users.order(:name).limit(50).to_a
    end
  end

  def advance
    @delivery = find_delivery
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
    @delivery = find_delivery
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
    attached = false
    if params[:photo_before].present?
      delivery.photo_before.attach(params[:photo_before])
      attached = true
    end
    if params[:photo_after].present?
      delivery.photo_after.attach(params[:photo_after])
      attached = true
    end
    delivery.record_proof_event!(actor: current_user) if attached
  end

  def find_delivery
    Delivery.joins(:communication)
            .where(org_unit: @store, communications: { tenant_id: tenant_scope.id })
            .includes(
              { delivery_answers: { image_attachment: :blob } },
              { delivery_comments: :user },
              communication: [ :communication_questions, :depends_on_communication ]
            )
            .find(params[:id])
  end

  def set_store
    # Inbox is store-scoped execution chrome; HQ/area must not use it as a board.
    unless store_user?
      redirect_to app_root_path, alert: t("auth.hq_required")
      return
    end

    @store = current_user.store_org_unit
    return if @store

    redirect_to app_root_path, alert: t("errors.no_store")
  end
end
