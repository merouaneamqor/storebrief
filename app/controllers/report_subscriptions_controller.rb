class ReportSubscriptionsController < ApplicationController
  before_action -> { require_hq_or_area(:reports) }
  before_action -> { require_feature!(:morocco_ops) }
  before_action -> { require_feature!(:reports) }
  before_action -> { require_feature!(:email_alerts) }
  before_action :require_report_recipient
  before_action :set_subscription

  def show
  end

  def update
    if @subscription.update(subscription_params)
      redirect_to report_subscription_path, notice: t("report_subscriptions.saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def require_report_recipient
    redirect_to app_root_path, alert: t("auth.hq_required") unless Reports::Audience.eligible?(current_user)
  end

  def set_subscription
    @subscription = current_user.report_subscription || current_user.build_report_subscription(tenant: tenant_scope)
  end

  def subscription_params
    params.require(:report_subscription).permit(:enabled, :frequency, :csv_attachment)
  end
end
