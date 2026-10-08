# frozen_string_literal: true

class DemoRequestsController < ApplicationController
  before_action :require_super_admin
  before_action :set_demo_request, only: :update

  def index
    @demo_requests = DemoRequest.order(created_at: :desc)
  end

  def update
    if @demo_request.update(status: params.require(:status))
      redirect_to demo_requests_path, notice: t("demo_requests.updated")
    else
      redirect_to demo_requests_path, alert: @demo_request.errors.full_messages.to_sentence
    end
  end

  private

  def set_demo_request
    @demo_request = DemoRequest.find(params[:id])
  end
end
