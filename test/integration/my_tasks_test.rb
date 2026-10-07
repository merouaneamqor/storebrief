require "test_helper"

class MyTasksTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("my-tasks", features: { morocco_ops: true })
  end

  def send_task(title, store: @brand.store, due_at: nil)
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Corps", format: "task",
      status: "draft", priority: "urgent"
    )
    brief.send_to!([ store.id ])
    delivery = brief.deliveries.first
    delivery.update!(due_at: due_at) if due_at
    delivery
  end

  test "store manager sees assigned open tasks with filters" do
    zone = Time.find_zone("Africa/Casablanca")
    late = send_task("En retard", due_at: zone.local(2026, 10, 1, 18, 0))
    today = send_task("Aujourd'hui", due_at: zone.local(2026, 10, 7, 18, 0))
    upcoming = send_task("Demain", due_at: zone.local(2026, 10, 8, 18, 0))

    travel_to zone.local(2026, 10, 7, 10, 0) do
      sign_in(@brand.store_user)
      get my_tasks_path
      assert_response :success
      assert_match late.communication.title, response.body
      assert_match today.communication.title, response.body
      assert_match upcoming.communication.title, response.body

      get my_tasks_path(filter: "overdue")
      assert_response :success
      assert_match late.communication.title, response.body
      assert_no_match today.communication.title, response.body

      get my_tasks_path(filter: "today")
      assert_match today.communication.title, response.body
      assert_no_match upcoming.communication.title, response.body
    end
  end

  test "hq is redirected away from my tasks" do
    sign_in(@brand.hq)
    get my_tasks_path
    assert_redirected_to app_root_path
  end
end
