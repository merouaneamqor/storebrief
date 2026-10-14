class CommunicationsController < ApplicationController
  layout :communications_layout

  before_action :require_compose_hq, except: %i[index show]
  before_action :require_monitor_access, only: %i[index show]
  before_action -> { require_feature!(:briefs) }
  before_action :set_communication, only: %i[show edit update send_brief notify_push stop_recurrence update_priority]
  before_action :load_target_units, only: %i[new create edit update]

  def index
    @communications = monitored_communications.includes(:author, :deliveries).order(created_at: :desc)
  end

  def show
    if @communication.draft?
      if hq_user?
        redirect_to edit_communication_path(@communication)
      else
        redirect_to app_root_path, alert: t("auth.hq_required")
      end
      return
    end

    @stats = @communication.completion_stats
    @deliveries = monitored_deliveries_for(@communication).includes(
      :org_unit, :assignee,
      photo_before_attachment: :blob,
      photo_after_attachment: :blob,
      delivery_answers: [ :communication_question, { image_attachment: :blob } ],
      delivery_events: :actor
    ).order(:id)
    @notifications = hq_user? ? @communication.notification_logs.includes(:user).order(created_at: :desc) : []
    @monitor_only = area_user?
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

  def preview_targets
    stores = Vazivo::Assignment.preview(
      tenant_scope,
      org_unit_ids: params[:org_unit_ids],
      **assignment_filter_kwargs
    )
    render json: {
      count: stores.size,
      stores: stores.map { |store| { id: store.id, name: store.name, store_format: store.store_format, cluster: store.cluster } },
      summary: t("communications.assignment_preview", count: stores.size)
    }
  end

  def send_brief
    if @communication.sent?
      redirect_to @communication, alert: t("communications.already_sent")
      return
    end

    begin
      @communication.send_to!(
        params[:org_unit_ids].presence || @communication.deliveries.pluck(:org_unit_id),
        **assignment_filter_kwargs
      )
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

  def require_compose_hq
    require_hq
  end

  def require_monitor_access
    require_hq_or_area(:monitor)
  end

  def communications_layout
    %w[new create edit update].include?(action_name) ? "brief_editor" : "application"
  end

  def set_communication
    @communication = monitored_communications.includes(:communication_questions).find(params[:id])
  end

  def monitored_communications
    scope = tenant_scope.communications
    return scope if hq_user?

    store_ids = area_store_ids
    return scope.none if store_ids.empty?

    scope.sent.where(id: Delivery.where(org_unit_id: store_ids).select(:communication_id))
  end

  def monitored_deliveries_for(communication)
    deliveries = communication.deliveries
    return deliveries if hq_user?

    deliveries.where(org_unit_id: area_store_ids)
  end

  def area_store_ids
    area = current_user&.area_org_unit
    return [] unless area

    area.descendant_stores.pluck(:id)
  end

  def load_target_units
    @target_units = tenant_scope.org_units.where(unit_type: %w[region store]).order(:unit_type, :name)
  end

  def persist_communication(failure_template)
    sending = params[:commit] == "send"
    @communication.status = "draft" unless sending

    if @communication.save
      if sending
        begin
          @communication.send_to!(params[:org_unit_ids], **assignment_filter_kwargs)
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

  def assignment_filter_kwargs
    {
      role: params[:assignment_role].presence,
      store_format: params[:store_format].presence,
      cluster: params[:cluster].presence
    }
  end

  def communication_params
    params.require(:communication).permit(
      :title_fr, :title_ar, :body_fr, :body_ar, :format, :priority,
      recurrence_attributes: [ :frequency, :interval, :ends_on, { weekdays: [] } ],
      communication_questions_attributes: [
        :id, :position, :question_type, :title_fr, :title_ar, :required, :options, :_destroy
      ]
    )
  end
end
