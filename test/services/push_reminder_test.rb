require "test_helper"

class PushReminderTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("push-reminder")
    @brand.store_user.push_subscriptions.create!(
      tenant: @brand.tenant,
      endpoint: "https://push.example.test/sub/reminder",
      p256dh: "BNcRdreALRP-Bx7SccKNqE-h4SZr3kGkFLXB",
      auth: "tBHItJI5svbpez7KI4CCXg"
    )
  end

  test "does nothing without VAPID keys" do
    send_checklist(age: 13.hours)

    assert_equal 0, PushReminder.notify_pending!
  end

  test "reminds stores about checklists pending for more than 12 hours, once a day" do
    delivery = send_checklist(age: 13.hours)

    pushes = capture_pushes { assert_equal 1, PushReminder.notify_pending! }
    assert_equal 1, pushes.size
    payload = JSON.parse(pushes.first[:message])
    assert_equal "Reminder", payload["title"]
    assert_equal "/checklists/deliveries/#{delivery.id}", payload["url"]

    capture_pushes { assert_equal 0, PushReminder.notify_pending! }
  end

  test "reminds stores about pending briefs" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Promo", body_fr: "Changer la vitrine.", format: "task", status: "draft"
    )
    brief.send_to!([ @brand.store.id ])
    delivery = brief.deliveries.first
    delivery.update_columns(created_at: 13.hours.ago)

    pushes = capture_pushes { assert_equal 1, PushReminder.notify_pending! }
    assert_equal "/inbox/#{delivery.id}", JSON.parse(pushes.first[:message])["url"]
  end

  test "skips fresh, completed, and stale deliveries" do
    send_checklist(age: 1.hour)
    send_checklist(age: 20.days)
    send_checklist(age: 13.hours).update!(status: "completed", completed_at: Time.current)

    capture_pushes { assert_equal 0, PushReminder.notify_pending! }
  end

  private

  def send_checklist(age:)
    checklist = @brand.tenant.checklists.create!(author: @brand.hq, title_fr: "Ouverture", status: "draft")
    checklist.checklist_items.create!(position: 0, title_fr: "Vitrine", requires_photo: false)
    checklist.send_to!([ @brand.store.id ])
    delivery = checklist.checklist_deliveries.first
    delivery.update_columns(created_at: age.ago)
    delivery
  end

  def capture_pushes
    sent = []
    with_vapid do
      WebPush.stub(:payload_send, ->(**kwargs) { sent << kwargs; true }) { yield }
    end
    sent
  end
end
