class InboxController < ApplicationController
  before_action -> { require_feature!(:briefs) }
  before_action :set_store

  def index
    @deliveries = Delivery.current_instances
                          .where(org_unit: @store, communications: { tenant_id: tenant_scope.id, status: "sent" })
                          .includes(:delivery_reads, communication: :depends_on_communication)
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
    submit_delivery do
      @delivery.save_answers!(params[:answers]) if params[:step].to_s == "done" && @delivery.communication.questions?
      @delivery.advance_awareness!(params[:step], by: current_user)
    end
  end

  def complete
    @delivery = find_delivery
    submit_delivery do
      @delivery.save_answers!(params[:answers]) if @delivery.communication.questions?
      if @delivery.communication.task?
        @delivery.complete!
      else
        @delivery.mark_read!(by: current_user)
      end
    end
  end

  private

  # Lock the delivery so a retried offline request cannot append the same files twice.
  # A failed completion rolls back attachments, answers and history together.
  def submit_delivery
    @delivery.with_lock do
      request_id = params[:proof_request_id].to_s.first(100).presence
      repeated = request_id && @delivery.delivery_events.where(kind: "proof").where("payload ->> 'request_id' = ?", request_id).exists?
      wrong_owner = params[:proof_owner].present? && params[:proof_owner] != "#{current_tenant.id}:#{current_user.id}"
      if wrong_owner || (!repeated && offline_conflict?(@delivery))
        render json: { status: "error", code: "conflict", message: t("offline_workspaces.conflict"), location: inbox_path(@delivery) }, status: :conflict
        return
      end
      unless repeated
        attached = attach_proof(@delivery)
        yield
        @delivery.record_proof_event!(actor: current_user, request_id: request_id) if attached || request_id
      end
    end
    notice = if @delivery.pending_approval?
      t("morocco.approval.submitted")
    elsif action_name == "advance"
      t("morocco.awareness.saved")
    elsif @delivery.communication.task?
      t("inbox.task_done")
    else
      t("inbox.marked_read")
    end
    respond_to do |format|
      format.html { redirect_to inbox_path(@delivery), notice: notice }
      format.json { render json: { status: "ok", delivery_status: @delivery.status, location: inbox_path(@delivery) } }
    end
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    message = e.is_a?(ArgumentError) ? e.message : e.record.errors.full_messages.to_sentence
    respond_to do |format|
      format.html { redirect_to inbox_path(@delivery), alert: message }
      format.json { render json: { status: "error", message: message }, status: :unprocessable_entity }
    end
  end

  def offline_conflict?(delivery)
    return false unless params[:proof_request_id].present?
    return false if params[:task_snapshot].blank?

    expected = [ delivery.id, delivery.updated_at.iso8601(6), delivery.communication.updated_at.iso8601(6) ]
    Rails.application.message_verifier(:offline_task).verified(params[:task_snapshot]) != expected
  end

  def attach_proof(delivery)
    uploads = [ params[:photo_before], params[:photo_after], *Array(params[:proof_files]) ].reject(&:blank?)
    unless uploads.all? { |file| file.is_a?(ActionDispatch::Http::UploadedFile) }
      raise ArgumentError, t("task_proof.invalid_type")
    end

    delivery.photo_before = params[:photo_before] if params[:photo_before].present?
    delivery.photo_after = params[:photo_after] if params[:photo_after].present?
    files = Array(params[:proof_files]).reject(&:blank?)
    delivery.proof_files = delivery.proof_files.blobs.to_a + files if files.any?
    attached = params[:photo_before].present? || params[:photo_after].present? || files.any?
    delivery.save! if attached
    attached
  end

  def find_delivery
    Delivery.joins(:communication)
            .where(org_unit: @store, communications: { tenant_id: tenant_scope.id })
            .includes(
              :delivery_reads,
              { proof_files_attachments: :blob },
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
