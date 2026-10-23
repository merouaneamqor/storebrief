require "test_helper"

class ReportDigestDeliveryTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @now = Time.find_zone!(Vazivo::Schedule::ZONE).local(2026, 3, 9, 9)
    travel_to @now
    @brand = build_brand("digest-svc")
    @area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    @brand.store.update!(name: "متجر الرباط")
    @hidden_region = @brand.tenant.org_units.create!(name: "Hidden region", unit_type: "region")
    @hidden = @brand.tenant.org_units.create!(name: "Hidden Store", unit_type: "store", parent: @hidden_region)
    @subscription = ReportSubscription.create!(tenant: @brand.tenant, user: @area, enabled: true, csv_attachment: true)
    make_due
    add_work(@brand, @brand.store, "completed")
    add_work(@brand, @brand.store, "pending")
    add_work(@brand, @hidden, "pending")
    other = build_brand("foreign-digest")
    add_work(other, other.store, "pending")
    ActionMailer::Base.deliveries.clear
  end

  teardown { travel_back }

  test "sweep sends a scoped digest, optional CSV, billed log and only one copy per period" do
    stale = ReportSubscription.find(@subscription.id)
    assert_emails 1 do
      ReportDigestJob.perform_now
      ReportDigestJob.perform_now
      Reports::DigestDelivery.deliver_due!(stale, now: @now)
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @area.email ], mail.to
    assert_includes mail.html_part.body.decoded, "50%"
    assert_includes mail.html_part.body.decoded, "متجر الرباط"
    refute_includes mail.html_part.body.decoded, "Hidden Store"
    assert_equal 1, mail.attachments.size
    assert_includes mail.attachments.first.decoded.force_encoding(Encoding::UTF_8), "متجر الرباط"
    log = @brand.tenant.notification_logs.where(notifiable: @subscription).sole
    assert_equal "sent", log.status
    assert log.billed?
    assert_equal 1, Vazivo::Billing.for(@brand.tenant).month_count
    assert_equal "weekly:2026-03-02:2026-03-08", @subscription.reload.last_sent_period
    assert_equal @now, @subscription.last_sent_at
    make_due
    assert_no_emails { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
    assert_equal 1, @brand.tenant.notification_logs.where(notifiable: @subscription).count
  end

  test "digest summary counts only scoped assigned work and overdue pending work" do
    digest = Reports::Digest.new(@area, date_range: @subscription.reporting_period(@now), now: @now)
    assert_equal 50, digest.compliance
    assert_equal 1, digest.overdue
    assert_equal [ @brand.store ], digest.top_stores.map(&:store)
    assert_equal [ @brand.store ], digest.bottom_stores.map(&:store)
  end

  test "own SMTP sends successfully without platform billing and attachment can be disabled" do
    @brand.tenant.create_mail_setting!(use_platform: false, smtp_address: "smtp.example.test", from_email: "ops@example.test")
    @subscription.update!(csv_attachment: false)
    assert_emails(1) { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
    mail = ActionMailer::Base.deliveries.last
    assert_empty mail.attachments
    assert_equal "smtp.example.test", mail.delivery_method.settings[:address]
    assert_not @brand.tenant.notification_logs.last.billed?
    assert_equal 0, Vazivo::Billing.for(@brand.tenant).month_count
  end

  test "SMTP failures are unbilled and retry at most once an hour" do
    message = Object.new
    def message.deliver_now
      raise Net::SMTPFatalError, "failed"
    end
    ReportMailer.stub(:digest, message) do
      assert_no_emails do
        Reports::DigestDelivery.deliver_due!(@subscription, now: @now)
        Reports::DigestDelivery.deliver_due!(@subscription, now: @now)
      end
    end
    log = @brand.tenant.notification_logs.where(notifiable: @subscription).sole
    assert_equal "failed", log.status
    assert_not log.billed?
    assert_nil @subscription.reload.last_sent_period
    assert_equal @now + 1.hour, @subscription.next_delivery_at
  end

  test "opt-out, revoked role, disabled tenant flags and missing platform SMTP prevent sends" do
    @area.update!(operational_email_opt_out: true)
    assert_no_emails { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
    @area.update!(operational_email_opt_out: false)
    @area.memberships.update_all(role: "store")
    make_due
    assert_no_emails { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
    @area.memberships.update_all(role: "area")
    %w[morocco_ops reports email_alerts].each do |flag|
      @brand.tenant.update!(features: @brand.tenant.features.merge(flag => false))
      @subscription.reload
      @subscription.tenant.reload
      make_due
      assert_no_emails { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
      @brand.tenant.update!(features: @brand.tenant.features.merge(flag => true))
    end
    @subscription.tenant.reload
    make_due
    PlatformMail.stub(:configured?, false) do
      assert_no_emails { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
    end
    assert_empty @brand.tenant.notification_logs.where(notifiable: @subscription)
  end

  test "custom scoped HQ reports permission restricts digest and revocation prevents delivery" do
    role = @brand.tenant.tenant_roles.create!(name: "Regional reports", base_role: "hq", capabilities: [ "reports" ])
    @brand.hq.memberships.first.update!(tenant_role: role)
    digest = Reports::Digest.new(@brand.hq.reload, date_range: @subscription.reporting_period(@now), now: @now)
    assert_equal [ @brand.store ], digest.ranking.rows.map(&:store)
    denied = @brand.tenant.tenant_roles.create!(name: "Area without reports", base_role: "area", capabilities: [ "monitor" ])
    @area.memberships.first.update!(tenant_role: denied)
    assert_no_emails { Reports::DigestDelivery.deliver_due!(@subscription, now: @now) }
    assert_empty @brand.tenant.notification_logs.where(notifiable: @subscription)
  end

  private

  def make_due
    @subscription.update_columns(next_delivery_at: @now - 1.hour)
  end

  def add_work(brand, store, status)
    brief = brand.tenant.communications.create!(author: brand.hq, title_fr: "Brief", body_fr: "Read", format: "news", status: "sent")
    delivery = brief.deliveries.create!(org_unit: store, status: status, due_at: @now - 2.days)
    delivery.update_columns(created_at: @now - 5.days)
  end
end
