class CommunicationsController < ApplicationController
  layout :communications_layout

  before_action :require_hq
  before_action :set_communication, only: %i[show edit update send_brief]
  before_action :load_target_units, only: %i[new create edit update]

  def index
    @communications = tenant_scope.communications.includes(:author, :deliveries).order(created_at: :desc)
  end

  def show
    if @communication.draft?
      redirect_to edit_communication_path(@communication)
      return
    end

    @stats = @communication.completion_stats
    @deliveries = @communication.deliveries.includes(:org_unit, delivery_answers: [:communication_question, { image_attachment: :blob }]).order(:id)
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
      :title_fr, :title_ar, :body_fr, :body_ar, :format,
      communication_questions_attributes: [
        :id, :position, :question_type, :title_fr, :title_ar, :required, :options, :_destroy
      ]
    )
  end
end
