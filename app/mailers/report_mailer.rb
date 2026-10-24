class ReportMailer < ApplicationMailer
  def digest(subscription:, date_range:, now: Time.current)
    @user = subscription.user
    @tenant = subscription.tenant
    @digest = Reports::Digest.new(@user, date_range: date_range, now: now)
    @date_range = date_range
    @preferences_url = report_subscription_url(host: ENV.fetch("APP_HOST", "localhost:3001"),
      protocol: ENV.fetch("APP_PROTOCOL", Rails.env.production? ? "https" : "http"))
    I18n.with_locale(@user.locale) do
      if subscription.csv_attachment?
        table = Reports::ExportTable.ranking(@digest.ranking)
        attachments["report-#{date_range.from}-#{date_range.to}.csv"] = {
          mime_type: "text/csv; charset=utf-8", content: Reports::Spreadsheet.new(headers: table.headers, rows: table.rows).csv
        }
      end
      setting = @tenant.mail_setting_or_build
      mail(to: @user.email, from: setting.from_address,
        subject: t("report_digest.subject", tenant: @tenant.name), delivery_method_options: setting.delivery_method_options)
    end
  end
end
