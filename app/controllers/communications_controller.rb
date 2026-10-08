class CommunicationsController < ApplicationController
  layout :communications_layout

  before_action :require_hq
  before_action -> { require_feature!(:briefs) }
  before_action :set_communication, only: %i[show edit update send_brief notify_push stop_recurrence update_priority update_dependency]
  before_action :load_target_units, only: %i[new create edit update]
  before_action :load_dependency_options, only: %i[new create edit update show]

  def index
    @communications = tenant_scope.communications.includes(:author, :deliveries).order(created_at: :desc)
  end

  def show
    if @communication.draft?
      redirect_to edit_communication_path(@communication)
      return
    end

    @stats = @communication.completion_stats
    @deliveries = @communication.deliveries.includes(
      :org_unit, :assignee,
      photo_before_attachment: :blob,
      photo_after_attachment: :blob,
      delivery_answers: [ :communication_question, { image_attachment: :blob } ]
    ).order(:id)
    @notifications = @communication.notification_logs.includes(:user).order(created_at: :desc)
  end

  def new
    @communication = tenant_scope.communications.new(format: "news")
  end

  def create
    @communication = tenant_scope.communications.new(communication_params)
    @communication.author = current_user
    persist_communication(:new)
  end

  def edit
    return if @communication.draft?

    redirect_to @communication, alert: t("communications.already_sent")
  end

  def update
    unless @communication.draft?
      redirect_to @communication, alert: t("communications.already_sent")
      return
    end

    @communication.assign_attributes(communication_params)
    persist_communication(:edit)
  end

  def send_brief
    if @communication.sent?
      redirect_to @communication, alert: t("communications.already_sent")
      return
    end

    begin
      @communication.send_to!(params[:org_unit_ids].presence || @communication.deliveries.pluck(:org_unit_id))
      redirect_to @communication, notice: t("communications.sent")
    rescue ArgumentError => e
      redirect_to @communication, alert: e.message
    end
  end

  def stop_recurrence
    unless @communication.recurrence_active?
      redirect_to @communication, alert: t("communications.recurrence.not_active")
      return
    end

    Vazivo::Recurrence.stop!(@communication)
    redirect_to @communication, notice: t("communications.recurrence.stopped")
  end

  # HQ can re-prioritise a task at any time, including after it was sent.
  def update_priority
    if @communication.task? && @communication.update(priority: params.dig(:communication, :priority))
      redirect_to @communication, notice: t("communications.priority_saved")
    else
      redirect_to @communication, alert: t("communications.priority_invalid")
    end
  end

  # HQ can clear or reassign a dependency at any time, including after send.
  def update_dependency
    unless @communication.task?
      redirect_to @communication, alert: t("communications.dependency.invalid")
      return
    end

    raw_id = params.dig(:communication, :depends_on_id).presence
    prerequisite = raw_id && tenant_scope.communications.where(format: "task").find_by(id: raw_id)
    if raw_id && prerequisite.nil?
      redirect_to @communication, alert: t("communications.dependency.invalid")
      return
    end

    @communication.depends_on = prerequisite
    if @communication.save
      notice = prerequisite ? t("communications.dependency.saved") : t("communications.dependency.cleared")
      redirect_to @communication, notice: notice
    else
      redirect_to @communication, alert: t("communications.dependency.invalid")
    end
  end

  def notify_push
    unless @communication.sent?
      redirect_to @communication, alert: t("communications.not_sent_yet")
      return
    end

    unless WebPushConfig.configured?
      redirect_to @communication, alert: t("communications.push_not_configured")
      return
    end

    pending = @communication.deliveries.pending.count
    if pending.zero?
      redirect_to @communication, notice: t("communications.push_none_pending")
      return
    end

    sent = PushNotifier.remind_communication!(@communication)
    notice =
      if sent.zero?
        t("communications.push_no_devices")
      else
        t("communications.push_sent", count: sent)
      end
    redirect_to @communication, notice: notice
  end

  private

  def communications_layout
    %w[new create edit update].include?(action_name) ? "brief_editor" : "application"
  end

  def set_communication
    @communication = tenant_scope.communications.includes(:communication_questions).find(params[:id])
  end

  def load_target_units
    @target_units = tenant_scope.org_units.where(unit_type: %w[region store]).order(:unit_type, :name)
  end

  def load_dependency_options
    scope = tenant_scope.communications.where(format: "task")
    scope = scope.where.not(id: @communication.id) if @communication&.persisted?
    @dependency_options = scope.order(created_at: :desc).limit(100)
  end

  def persist_communication(failure_template)
    sending = params[:commit] == "send"
    @communication.status = "draft" unless sending

    if @communication.save
      if sending
        begin
          @communication.send_to!(params[:org_unit_ids])
          redirect_to @communication, notice: t("communications.sent")
        rescue ArgumentError => e
          flash.now[:alert] = e.message
          render failure_template, status: :unprocessable_entity
        end
      else
        redirect_to edit_communication_path(@communication), notice: t("communications.draft_saved")
      end
    else
      render failure_template, status: :unprocessable_entity
    end
  end

  def communication_params
    params.require(:communication).permit(
      :title_fr, :title_ar, :body_fr, :body_ar, :format, :priority, :depends_on_id,
      recurrence_attributes: [ :frequency, :interval, :ends_on, { weekdays: [] } ],
      communication_questions_attributes: [
        :id, :position, :question_type, :title_fr, :title_ar, :required, :options, :_destroy
      ]
    )
  end
end
