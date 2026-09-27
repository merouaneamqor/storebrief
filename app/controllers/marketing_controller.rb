class MarketingController < ApplicationController
  skip_before_action :require_login
  skip_before_action :bind_session_tenant
  before_action :redirect_tenant_host
  layout "marketing"

  def show
    redirect_to app_root_path if current_user
    @demo_request = DemoRequest.new(preferred_locale: I18n.locale.to_s)
  end

  def resources
  end

  def strategy
    path = Rails.root.join("docs/morocco-90-day-marketing-strategy.md")
    @strategy_markdown = File.read(path)
  end

  def create_demo
    @demo_request = DemoRequest.new(demo_request_params)

    if @demo_request.save
      DemoRequestMailer.received(@demo_request).deliver_now
      redirect_to root_path(anchor: "demo"), notice: t("landing.demo.success")
    else
      flash.now[:alert] = @demo_request.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private

  def demo_request_params
    params.require(:demo_request).permit(:name, :company, :email, :phone, :store_count, :preferred_locale)
  end

  def redirect_tenant_host
    return unless host_tenant?

    redirect_to(current_user ? app_root_path : login_path)
  end
end
