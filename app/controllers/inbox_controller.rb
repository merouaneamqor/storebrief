class InboxController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action :set_store

  def index
    @deliveries = Delivery.joins(:communication)
                          .where(org_unit: @store, communications: { tenant_id: tenant_scope.id, status: "sent" })
                          .includes(:communication)
                          .order("communications.created_at DESC")
  end

  def show
    @delivery = find_delivery
    @communication = @delivery.communication
    @questions = @communication.communication_questions
    @answers = @delivery.delivery_answers.index_by(&:communication_question_id)
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
    delivery.photo_before.attach(params[:photo_before]) if params[:photo_before].present?
    delivery.photo_after.attach(params[:photo_after]) if params[:photo_after].present?
  end

  def find_delivery
    Delivery.joins(:communication)
            .where(org_unit: @store, communications: { tenant_id: tenant_scope.id })
            .includes(:communication, { delivery_answers: { image_attachment: :blob } }, communication: :communication_questions)
            .find(params[:id])
  end

  def set_store
    @store = current_user.store_org_unit
    return if @store

    redirect_to app_root_path, alert: t("errors.no_store")
  end
end
