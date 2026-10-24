require "test_helper"

class ReportMailerTest < ActionMailer::TestCase
  test "digest and optional CSV use each recipient locale including Arabic RTL" do
    brand = build_brand("digest-mailer")
    subscription = ReportSubscription.create!(tenant: brand.tenant, user: brand.hq, enabled: true, csv_attachment: true)
    range = Reports::DateRange.new(from: "2026-03-02", to: "2026-03-08")
    %w[fr ar en es].each do |locale|
      brand.hq.update!(locale: locale)
      subscription.user.reload
      mail = ReportMailer.digest(subscription: subscription, date_range: range)
      assert_equal I18n.t("report_digest.subject", locale: locale, tenant: brand.tenant.name), mail.subject
      assert_includes mail.html_part.body.decoded, I18n.t("report_digest.empty", locale: locale)
      assert_includes mail.html_part.body.decoded, "dir=\"#{locale == 'ar' ? 'rtl' : 'ltr'}\""
      assert_includes mail.attachments.first.decoded.force_encoding(Encoding::UTF_8), I18n.t("spreadsheet_exports.columns.store", locale: locale)
      refute_includes mail.body.decoded, "translation missing"
    end
  end
end
