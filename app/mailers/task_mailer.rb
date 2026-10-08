class TaskMailer < ApplicationMailer
  def communication_assigned(user:, communication:, delivery:)
    @user = user
    @communication = communication
    @delivery = delivery
    @tenant = params[:tenant] || communication.tenant
    @url = inbox_url_for(delivery)
    I18n.with_locale(user.locale.presence || I18n.default_locale) do
      mail(
        to: user.email,
        from: from_for(@tenant),
        subject: t("mailers.task.communication_subject", title: communication.localized_value(:title, locale: I18n.locale)),
        delivery_method_options: @tenant.mail_setting_or_build.delivery_method_options
      )
    end
  end

  def checklist_assigned(user:, checklist:, delivery:)
    @user = user
    @checklist = checklist
    @delivery = delivery
    @tenant = params[:tenant] || checklist.tenant
    @url = checklist_url_for(delivery)
    I18n.with_locale(user.locale.presence || I18n.default_locale) do
      mail(
        to: user.email,
        from: from_for(@tenant),
        subject: t("mailers.task.checklist_subject", title: checklist.localized_value(:title, locale: I18n.locale)),
        delivery_method_options: @tenant.mail_setting_or_build.delivery_method_options
      )
    end
  end

  private

  def from_for(tenant)
    tenant.mail_setting_or_build.from_address
  end

  def inbox_url_for(delivery)
    host = ENV.fetch("APP_HOST", "localhost:3001")
    protocol = ENV.fetch("APP_PROTOCOL", Rails.env.production? ? "https" : "http")
    "#{protocol}://#{host}/inbox/#{delivery.id}"
  end

  def checklist_url_for(delivery)
    host = ENV.fetch("APP_HOST", "localhost:3001")
    protocol = ENV.fetch("APP_PROTOCOL", Rails.env.production? ? "https" : "http")
    "#{protocol}://#{host}/checklists/deliveries/#{delivery.id}"
  end
end
