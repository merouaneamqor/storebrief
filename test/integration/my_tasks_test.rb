require "test_helper"

class MyTasksTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("my-tasks", features: { morocco_ops: true })
    @tenant = @brand.tenant
    @area = @tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @other_area = @tenant.org_units.create!(name: "Sud", unit_type: "area", parent: @brand.region)
    @north = @tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @area)
    @south = @tenant.org_units.create!(name: "Agadir", unit_type: "store", parent: @other_area)
    @store_user = create_user(@tenant, org_unit: @north, role: :store, email: "store-north@my-tasks.test")
    @area_user = create_user(@tenant, org_unit: @area, role: :area, email: "area-nord@my-tasks.test")
    @other_area_user = create_user(@tenant, org_unit: @other_area, role: :area, email: "area-sud@my-tasks.test")
  end

  test "store and area see open tasks with overdue today and upcoming filters" do
    travel_to Vazivo::Schedule::ZONE.parse("2026-10-07 10:00") do
      overdue = send_task("Vitrine en retard", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-06 09:00"), priority: "urgent")
      today = send_task("Facing du jour", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-07 18:00"), priority: "important")
      upcoming = send_task("Inventaire", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-09 11:00"))
      send_task("Note magasin", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-07 12:00"), format: "news")
      done = send_task("Deja fait", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-07 12:00"))
      done.deliveries.first.complete!
      checklist = open_checklist("Ouverture", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-07 16:00"))

      sign_in(@store_user)
      get my_tasks_path
      assert_response :success
      assert_match "Vitrine en retard", response.body
      assert_match "Facing du jour", response.body
      assert_match "Inventaire", response.body
      assert_match "Ouverture", response.body
      assert_no_match "Note magasin", response.body
      assert_no_match "Deja fait", response.body

      get my_tasks_path(filter: "overdue")
      assert_match "Vitrine en retard", response.body
      assert_no_match "Facing du jour", response.body
      assert_no_match "Inventaire", response.body

      get my_tasks_path(filter: "today")
      assert_match "Facing du jour", response.body
      assert_match "Ouverture", response.body
      assert_no_match "Vitrine en retard", response.body
      assert_no_match "Inventaire", response.body

      get my_tasks_path(filter: "upcoming")
      assert_match "Inventaire", response.body
      assert_no_match "Facing du jour", response.body

      get my_task_path(overdue.deliveries.first, kind: "task")
      assert_response :success
      assert_match "Vitrine en retard", response.body
      assert_match inbox_path(overdue.deliveries.first), response.body

      get my_task_path(checklist.checklist_deliveries.first, kind: "checklist")
      assert_response :success
      assert_match checklists_delivery_path(checklist.checklist_deliveries.first), response.body
    end
  end

  test "area sees descendant stores and not a neighbouring area" do
    travel_to Vazivo::Schedule::ZONE.parse("2026-10-07 10:00") do
      send_task("Tache Tanger", @north, due_at: Vazivo::Schedule::ZONE.parse("2026-10-07 15:00"))
      send_task("Tache Agadir", @south, due_at: Vazivo::Schedule::ZONE.parse("2026-10-07 15:00"))

      sign_in(@area_user)
      get my_tasks_path
      assert_response :success
      assert_match "Tache Tanger", response.body
      assert_match "Tanger", response.body
      assert_no_match "Tache Agadir", response.body
      assert_no_match "Agadir", response.body

      foreign = @tenant.communications.order(:id).last
      get my_task_path(foreign.deliveries.first, kind: "task")
      assert_redirected_to my_tasks_path
    end
  end

  test "a store user does not see another store" do
    send_task("Secret Agadir", @south, due_at: 1.hour.from_now)
    sign_in(@store_user)
    get my_tasks_path
    assert_response :success
    assert_no_match "Secret Agadir", response.body
    assert_no_match "Agadir", response.body
  end

  test "another tenant stays invisible" do
    other = build_brand("other-tasks", features: { morocco_ops: true })
    brief = other.tenant.communications.create!(
      author: other.hq, title_fr: "Foreign task", body_fr: "x", format: "task", status: "draft"
    )
    brief.send_to!([ other.store.id ])

    sign_in(@area_user)
    get my_tasks_path
    assert_no_match "Foreign task", response.body
  end

  test "briefs feature is required" do
    quiet = build_brand("no-briefs", features: { briefs: false, morocco_ops: true })
    sign_in(quiet.store_user)
    get my_tasks_path
    assert_redirected_to app_root_path
  end

  test "nav exposes my tasks for store and area" do
    sign_in(@store_user)
    get my_tasks_path
    assert_select "a[href='#{my_tasks_path}']"

    delete logout_path
    sign_in(@other_area_user)
    get app_root_path
    assert_select "a[href='#{my_tasks_path}']"
  end

  private

  def send_task(title, store, due_at:, priority: "routine", format: "task")
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Corps", format: format,
      status: "draft", priority: format == "task" ? priority : "routine"
    )
    brief.send_to!([ store.id ])
    brief.deliveries.first.update!(due_at: due_at)
    brief
  end

  def open_checklist(title, store, due_at:)
    checklist = @tenant.checklists.create!(author: @brand.hq, title_fr: title, status: "sent")
    checklist.checklist_deliveries.create!(org_unit: store, status: "pending", due_at: due_at)
    checklist
  end
end
