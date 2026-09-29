class ChecklistsController < ApplicationController
  before_action :require_hq
  before_action -> { require_feature!(:checklists) }
  before_action :set_checklist, only: %i[show send_checklist notify_push]

  def index
    @checklists = tenant_scope.checklists.includes(:author, :checklist_deliveries).order(created_at: :desc)
  end

  def show
    @stats = @checklist.completion_stats
    @deliveries = @checklist.checklist_deliveries.includes(:org_unit).order(:id)
    @notifications = @checklist.notification_logs.includes(:user).order(created_at: :desc)
    @target_units = tenant_scope.org_units.where(unit_type: %w[region store]).order(:unit_type, :name)
  end

  def send_checklist
    if @checklist.sent?
      redirect_to @checklist, alert: t("communications.already_sent")
      return
    end

    begin
      @checklist.send_to!(params[:org_unit_ids])
      redirect_to @checklist, notice: t("checklists.sent")
    rescue ArgumentError => e
      redirect_to @checklist, alert: e.message
    end
  end

  def notify_push
    unless @checklist.sent?
      redirect_to @checklist, alert: t("communications.not_sent_yet")
      return
    end

    unless WebPushConfig.configured?
      redirect_to @checklist, alert: t("communications.push_not_configured")
      return
    end

    pending = @checklist.checklist_deliveries.pending.count
    if pending.zero?
      redirect_to @checklist, notice: t("communications.push_none_pending")
      return
    end

    sent = PushNotifier.remind_checklist!(@checklist)
    redirect_to @checklist, notice: t("communications.push_sent", count: sent)
  end

  private

  def set_checklist
    @checklist = tenant_scope.checklists.find(params[:id])
  end
end
