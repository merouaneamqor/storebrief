require "test_helper"
require "fugit"

# Proves execution sweeps and report digests are wired into the production
# schedule (config/recurring.yml + Solid Queue) and are safe to run repeatedly.
class ScheduledJobsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @brand = build_brand("scheduled-jobs")
  end

  test "recurring.yml schedules execution and report jobs in production" do
    config = YAML.safe_load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true)
    tasks = config.fetch("production")

    assert_equal %w[EscalationJob RecurringTaskJob ReportDigestJob], tasks.values.map { |t| t.fetch("class") }.sort
    assert_equal "every hour", tasks.fetch("report_digest").fetch("schedule")
    tasks.each_value do |task|
      assert task["class"].constantize < ApplicationJob
      assert Fugit.parse(task.fetch("schedule")), "invalid schedule #{task['schedule']}"
    end
  end

  test "production uses Solid Queue and bin/jobs exists" do
    assert_match(/queue_adapter = :solid_queue/, Rails.root.join("config/environments/production.rb").read)
    assert Rails.root.join("bin/jobs").executable?
    assert defined?(SolidQueue)
  end

  test "scheduled jobs can be enqueued on the default queue" do
    assert_enqueued_with(job: RecurringTaskJob, queue: "default") { RecurringTaskJob.perform_later }
    assert_enqueued_with(job: EscalationJob, queue: "default") { EscalationJob.perform_later }
    assert_enqueued_with(job: ReportDigestJob, queue: "default") { ReportDigestJob.perform_later }
  end

  test "running the escalation job twice does not duplicate escalation events" do
    delivery = overdue_delivery(@brand, due_ago: 73.hours)

    EscalationJob.perform_now
    assert_no_difference -> { EscalationEvent.count } do
      EscalationJob.perform_now
    end

    assert_equal 3, delivery.reload.escalation_level
  end

  test "escalation job records events under the tenant that owns each delivery" do
    other = build_brand("scheduled-jobs-other")
    mine = overdue_delivery(@brand, due_ago: 30.hours)
    theirs = overdue_delivery(other, due_ago: 30.hours)

    EscalationJob.perform_now

    assert_equal [ @brand.tenant.id ], mine.escalation_events.pluck(:tenant_id).uniq
    assert_equal [ other.tenant.id ], theirs.escalation_events.pluck(:tenant_id).uniq
  end

  test "running the recurring job twice on the same day creates one occurrence" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Facing", body_fr: "Facing", format: "task", status: "draft",
      recurrence_rule: { "frequency" => "daily" }
    )
    brief.send_to!([ @brand.store.id ])
    brief.reload.deliveries.each(&:complete!)
    day = brief.reload.recurrence_next_on

    travel_to Vazivo::Schedule::ZONE.local(day.year, day.month, day.day, 8, 0) do
      assert_difference -> { Communication.count }, 1 do
        RecurringTaskJob.perform_now
        RecurringTaskJob.perform_now
      end
    end
    assert_equal 1, brief.occurrences.count
  end

  private

  def overdue_delivery(brand, due_ago:)
    brief = brand.tenant.communications.create!(
      author: brand.hq, title_fr: "Stock", body_fr: "Stock", format: "task", status: "draft"
    )
    brief.send_to!([ brand.store.id ])
    brief.deliveries.first.tap { |d| d.update!(due_at: due_ago.ago, created_at: due_ago.ago - 1.hour) }
  end
end
