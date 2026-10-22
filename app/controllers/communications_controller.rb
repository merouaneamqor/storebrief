class CommunicationsController < ApplicationController
  layout :communications_layout

  before_action :require_compose_hq, except: %i[index show approve reject]
  before_action :require_approver, only: %i[approve reject]
  before_action :require_monitor_access, only: %i[index show]
  before_action -> { require_feature!(:briefs) }
  before_action :set_communication, only: %i[show edit update send_brief approve reject notify_push stop_recurrence update_priority save_as_template clear_dependency]
  before_action :load_target_units, only: %i[new create edit update]
  before_action :load_dependency_candidates, only: %i[new create edit update]

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
    @read_receipts = @communication.read_receipt_stats
    @deliveries = monitored_deliveries_for(@communication).includes(
      :org_unit, :assignee, :corrective_communication, :dependency_cleared_by,
      :delivery_reads,
      photo_before_attachment: :blob,
      photo_after_attachment: :blob,
      proof_files_attachments: :blob,
      delivery_answers: [ :communication_question, { image_attachment: :blob } ],
      delivery_events: :actor,
      delivery_comments: :user,
      org_unit: { memberships: :user }
    ).order(:id)
    @mentionable_users = tenant_scope.users.order(:name).limit(50).to_a if tenant_feature?(:morocco_ops)
    @notifications = hq_user? ? @communication.notification_logs.includes(:user).order(created_at: :desc) : []
    @monitor_only = area_user?
    if tenant_feature?(:morocco_ops)
      @store_visits = tenant_scope.visits.active
                                  .where(org_unit_id: @deliveries.map(&:org_unit_id))
                                  .upcoming_first
                                  .group_by(&:org_unit_id)
    end
  end

  def new
    @communication = tenant_scope.communications.new(format: "news")
  end

  def create
    @communication = tenant_scope.communications.new(communication_params)
    @communication.author = current_user
    apply_attachment_uploads!(@communication)
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
    attachments_touched = purge_removed_attachments!(@communication)
    attachments_touched = apply_attachment_uploads!(@communication) || attachments_touched
    @communication.reset_review! if attachments_touched
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

    if approval_pending_for_send?
      submit_for_review
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

  def approve
    decide_review("approved")
  end

  def reject
    decide_review("rejected")
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

  def save_as_template
    template = CommunicationTemplate.from_communication(@communication)

    if template.save
      redirect_to task_templates_path, notice: t("task_templates.saved", title: template.title)
    else
      redirect_back fallback_location: communication_path(@communication),
                    alert: t("task_templates.save_failed")
    end
  end

  def clear_dependency
    unless @communication.depends_on_another?
      redirect_to @communication, alert: t("morocco.dependency.none")
      return
    end

    @communication.clear_dependency!
    redirect_to @communication, notice: t("morocco.dependency.cleared_task")
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

  def require_approver
    return if hq_user? && user_allows?(:approve)

    redirect_to app_root_path, alert: t("approval.errors.not_allowed")
  end

  # Approval is required for this brief and it has not been approved yet.
  def approval_pending_for_send?
    Vazivo::Approval.gate?(@communication) && !@communication.review_approved?
  end

  def submit_for_review(redirect: nil)
    Vazivo::Approval.submit!(@communication, actor: current_user) unless @communication.review_pending?
    redirect_to redirect || edit_communication_path(@communication), notice: t("approval.submitted")
  end

  def decide_review(decision)
    Vazivo::Approval.decide!(@communication, approver: current_user, decision: decision,
                                             note: params[:review_note])
    redirect_to edit_communication_path(@communication), notice: t("approval.#{decision}")
  rescue Vazivo::Approval::Error => e
    redirect_to edit_communication_path(@communication), alert: e.message
  end

  def communications_layout
    %w[new create edit update].include?(action_name) ? "brief_editor" : "application"
  end

  def set_communication
    @communication = monitored_communications
                     .includes(:communication_questions, :visit, :depends_on_communication,
                               source_delivery: :communication,
                               attachments_attachments: :blob)
                     .find(params[:id])
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
    @target_units = tenant_scope.org_units.where(unit_type: %w[region area store]).order(:unit_type, :name)
  end

  def load_dependency_candidates
    scope = tenant_scope.communications.sent.where(format: "task").order(created_at: :desc).limit(50)
    scope = scope.where.not(id: @communication.id) if @communication&.persisted?
    @dependency_candidates = scope
  end

  def persist_communication(failure_template)
    sending = params[:commit] == "send"
    @communication.status = "draft" unless sending

    if @communication.save
      if sending && approval_pending_for_send?
        submit_for_review(redirect: edit_communication_path(@communication))
      elsif sending
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
    permitted = params.require(:communication).permit(
      :title_fr, :title_ar, :body_fr, :body_ar, :format, :priority, :depends_on_communication_id,
      :requires_approval, :due_at, :critical_broadcast, :requires_acknowledgement,
      :broadcast_email, :broadcast_whatsapp,
      recurrence_attributes: [ :frequency, :interval, :ends_on, { weekdays: [] } ],
      communication_questions_attributes: [
        :id, :position, :question_type, :title_fr, :title_ar, :required, :options, :_destroy
      ]
    )
    # Deadline is entered in store local time (Africa/Casablanca); blank falls back to Schedule.default_due.
    permitted[:due_at] = Vazivo::Schedule.parse_local(permitted[:due_at]) if permitted.key?(:due_at)
    permitted
  end

  def apply_attachment_uploads!(communication)
    files = Array(params.dig(:communication, :attachments)).compact_blank
    communication.attachments.attach(files) if files.any?
    files.any?
  end

  def purge_removed_attachments!(communication)
    ids = Array(params.dig(:communication, :remove_attachment_ids)).map(&:to_i).reject(&:zero?)
    return false if ids.empty?

    communication.attachments.attachments.where(id: ids).find_each(&:purge)
    true
  end
end
