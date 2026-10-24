class MarketingController < ApplicationController
  skip_before_action :require_login
  skip_before_action :bind_session_tenant
  skip_before_action :require_privacy_acceptance
  before_action :redirect_tenant_host
  layout "marketing"
  rate_limit to: 10, within: 1.minute, only: :create_demo,
             with: -> { redirect_to root_path(anchor: "demo"), alert: t("pricing.too_many") }

  def show
    redirect_to app_root_path if current_user
    plan = params[:plan].to_s
    @demo_request = DemoRequest.new(preferred_locale: I18n.locale.to_s,
                                    requested_plan: (plan if DemoRequest.sellable_plan_keys.include?(plan)))
  end

  def resources
  end

  def create_demo
    # Honeypot: bots fill the hidden field. Pretend success, store nothing.
    return redirect_to(root_path(anchor: "demo"), notice: t("landing.demo.success")) if params[:website].present?

    @demo_request = DemoRequest.new(demo_request_params)
    @demo_request.privacy_consent = params.dig(:demo_request, :privacy_consent)

    if @demo_request.save
      begin
        DemoRequestMailer.received(@demo_request).deliver_now
      rescue StandardError => e
        Rails.logger.error("[demo_request] mail failed id=#{@demo_request.id}: #{e.class}: #{e.message}")
      end
      redirect_to root_path(anchor: "demo"), notice: t("landing.demo.success")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def demo_request_params
    params.require(:demo_request).permit(
      :name, :company, :email, :phone, :store_count, :preferred_locale,
      :marketing_contact_consent, :privacy_consent,
      :country, :requested_plan, :requirements
    )
  end

  def redirect_tenant_host
    return unless host_tenant?

    redirect_to(current_user ? app_root_path : login_path)
  end
end
