class BillingsController < ApplicationController
  before_action :require_hq

  def show
    @billing = Vazivo::Billing.for(tenant_scope)
    @mail_setting = tenant_scope.mail_setting_or_build
  end

  def update
    setting = tenant_scope.mail_setting_or_build
    if setting.update(mail_params)
      redirect_to billing_path, notice: t("billing.saved")
    else
      @billing = Vazivo::Billing.for(tenant_scope)
      @mail_setting = setting
      flash.now[:alert] = setting.errors.full_messages.to_sentence.presence || t("billing.save_failed")
      render :show, status: :unprocessable_entity
    end
  end

  private

  def mail_params
    params.require(:tenant_mail_setting).permit(
      :use_platform, :from_email, :from_name,
      :smtp_address, :smtp_port, :smtp_domain,
      :smtp_username, :smtp_password,
      :smtp_authentication, :smtp_enable_starttls_auto
    )
  end
end
