class CommunicationsController < ApplicationController
  before_action :require_hq
  before_action :set_communication, only: %i[show send_brief]

  def index
    @communications = tenant_scope.communications.includes(:author, :deliveries).order(created_at: :desc)
  end

  def show
    @stats = @communication.completion_stats
    @deliveries = @communication.deliveries.includes(:org_unit).order(:id)
  end

  def new
    @communication = tenant_scope.communications.new(format: "news")
    @target_units = tenant_scope.org_units.where(unit_type: %w[region store]).order(:unit_type, :name)
  end

  def create
    @communication = tenant_scope.communications.new(communication_params)
    @communication.author = current_user
    @target_units = tenant_scope.org_units.where(unit_type: %w[region store]).order(:unit_type, :name)

    if params[:commit] == "Send"
      if @communication.save
        begin
          @communication.send_to!(params[:org_unit_ids])
          redirect_to @communication, notice: "Brief sent to stores."
        rescue ArgumentError => e
          @communication.destroy
          @communication = tenant_scope.communications.new(communication_params)
          flash.now[:alert] = e.message
          render :new, status: :unprocessable_entity
        end
      else
        render :new, status: :unprocessable_entity
      end
    else
      @communication.status = "draft"
      if @communication.save
        redirect_to @communication, notice: "Draft saved."
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def send_brief
    if @communication.sent?
      redirect_to @communication, alert: "Already sent."
      return
    end

    begin
      @communication.send_to!(params[:org_unit_ids].presence || @communication.deliveries.pluck(:org_unit_id))
      redirect_to @communication, notice: "Brief sent to stores."
    rescue ArgumentError => e
      redirect_to @communication, alert: e.message
    end
  end

  private

  def set_communication
    @communication = tenant_scope.communications.find(params[:id])
  end

  def communication_params
    params.require(:communication).permit(:title, :body, :format)
  end
end
