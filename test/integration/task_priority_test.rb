require "test_helper"

class TaskPriorityTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("priority-ui", features: { morocco_ops: true })
    @tenant = @brand.tenant
  end

  def send_task(title, priority: nil, format: "task", due_at: nil)
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Corps", format: format,
      status: "draft", priority: priority || "routine"
    )
    brief.send_to!([ @brand.store.id ])
    brief.deliveries.first.update!(due_at: due_at) if due_at
    brief
  end

  test "priority defaults to routine and rejects unknown values" do
    brief = send_task("Defaut")
    assert_equal "routine", brief.priority

    brief.priority = "whenever"
    assert_not brief.valid?
  end

  test "a note is always routine" do
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Info", body_fr: "Corps", format: "news", priority: "urgent"
    )
    assert_equal "routine", brief.priority
  end

  test "HQ stores a priority when composing a task" do
    sign_in @brand.hq
    post communications_path, params: {
      communication: { title_fr: "Rupture", body_fr: "Corps", format: "task", priority: "urgent" },
      org_unit_ids: [ @brand.store.id ], commit: "send"
    }
    assert_equal "urgent", @tenant.communications.order(:id).last.priority
  end

  test "the editor offers the priority choices" do
    sign_in @brand.hq
    get new_communication_path
    assert_select "input[type=radio][name='communication[priority]']", count: 3
  end

  test "HQ can change the priority of a sent task" do
    brief = send_task("A requalifier")
    sign_in @brand.hq

    patch priority_communication_path(brief), params: { communication: { priority: "important" } }
    assert_redirected_to communication_path(brief)
    assert_equal "important", brief.reload.priority

    patch priority_communication_path(brief), params: { communication: { priority: "bogus" } }
    assert_equal "important", brief.reload.priority
  end

  test "a store user cannot change priority" do
    brief = send_task("Interdit")
    sign_in @brand.store_user

    patch priority_communication_path(brief), params: { communication: { priority: "urgent" } }
    assert_equal "routine", brief.reload.priority
  end

  test "another tenant cannot change priority" do
    other = build_brand("priority-other")
    brief = send_task("Autre marque")
    sign_in other.hq

    patch priority_communication_path(brief), params: { communication: { priority: "urgent" } }
    assert_response :not_found
    assert_equal "routine", brief.reload.priority
  end

  test "the store inbox lists urgent tasks first" do
    send_task("Routine ancienne")
    send_task("Important", priority: "important")
    send_task("Urgent recent", priority: "urgent")
    sign_in @brand.store_user

    get inbox_index_path
    assert_response :success
    titles = css_select(".list li a").map(&:text)
    assert_equal [ "Urgent recent", "Important", "Routine ancienne" ], titles
    assert_select ".badge--priority-urgent", text: "Urgent"
  end

  test "the radar sorts by priority before deadline" do
    travel_to Vazivo::Schedule::ZONE.local(2026, 10, 7, 11, 0) do
      send_task("Routine en retard", due_at: 2.hours.ago)
      send_task("Urgent plus tard", priority: "urgent", due_at: 5.hours.from_now)
      snapshot = Vazivo::Radar.for(user: @brand.store_user, tenant: @tenant)

      items = snapshot.now_items + snapshot.later_items
      assert_equal [ "Urgent plus tard", "Routine en retard" ], items.map(&:title)
      assert_equal "urgent", items.first.priority
    end
  end

  test "the HQ board ranks higher priority first within a severity" do
    send_task("Retard routine", due_at: 5.hours.ago)
    send_task("Retard urgent", priority: "urgent", due_at: 1.hour.ago)
    board = Vazivo::HqBoard.for(@tenant)

    assert_equal [ "Retard urgent", "Retard routine" ], board.overdue.map(&:status_label)
    assert_equal "urgent", board.overdue.first.priority
  end

  test "a recurring task keeps its priority on each occurrence" do
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Facing", body_fr: "Corps", format: "task",
      priority: "important", recurrence_attributes: { frequency: "daily" }
    )
    brief.send_to!([ @brand.store.id ])
    brief.deliveries.first.update!(status: "completed")

    occurrence = Vazivo::Recurrence.spawn!(brief, today: brief.recurrence_next_on)
    assert_equal "important", occurrence.priority
  end

  test "priority labels exist in every locale" do
    %i[fr en es ar].each do |locale|
      Communication::PRIORITIES.each do |key|
        assert I18n.exists?("common.priorities.#{key}", locale), "#{locale} #{key}"
      end
      %w[priority priority_saved priority_invalid].each do |key|
        assert I18n.exists?("communications.#{key}", locale), "#{locale} #{key}"
      end
    end
  end
end
