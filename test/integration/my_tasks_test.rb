require "test_helper"

class MyTasksTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("vazivo-my-tasks")
    @tenant = @brand.tenant
    @region = @brand.region
    @store = @brand.store
    @second_store = @tenant.org_units.create!(name: "Rabat", unit_type: "store", parent: @region)
    @area_unit = @tenant.org_units.create!(name: "Casa Area", unit_type: "area", parent: @region)
    @store.update!(parent: @area_unit)
    @second_store.update!(parent: @area_unit)
    @area_user = create_user(@tenant, org_unit: @area_unit, role: :area, email: "area@#{@tenant.slug}.test")
    @second_store_user = create_user(@tenant, org_unit: @second_store, role: :store, email: "store2@#{@tenant.slug}.test")
  end

  test "store user sees their stores open tasks grouped by filters" do
    casa = Vazivo::Schedule::ZONE
    travel_to casa.local(2026, 10, 7, 10, 0) do
      seed_task("Vitrine à refaire", due_at: casa.local(2026, 10, 7, 7, 0), store: @store)
      seed_task("Caisse ouvrante", due_at: casa.local(2026, 10, 7, 14, 0), store: @store)
      seed_task("Préparer rayon", due_at: casa.local(2026, 10, 10, 10, 0), store: @store)

      sign_in(@brand.store_user)
      get inbox_index_path

      assert_response :success
      assert_select "h1", text: I18n.t("inbox.my_tasks.title", locale: :en)
      assert_select "a.filter-chip.is-active", text: /#{Regexp.escape(I18n.t('inbox.my_tasks.filters.all', locale: :en))}/
      assert_match "Vitrine à refaire", response.body
      assert_match "Caisse ouvrante", response.body
      assert_match "Préparer rayon", response.body

      get inbox_index_path(scope: "overdue")
      assert_match "Vitrine à refaire", response.body
      assert_no_match(/Caisse ouvrante/, response.body)
      assert_no_match(/Préparer rayon/, response.body)
      assert_select "a.filter-chip.is-active", text: /#{Regexp.escape(I18n.t('inbox.my_tasks.filters.overdue', locale: :en))}/

      get inbox_index_path(scope: "today")
      assert_match "Caisse ouvrante", response.body
      assert_no_match(/Vitrine à refaire/, response.body)
      assert_no_match(/Préparer rayon/, response.body)

      get inbox_index_path(scope: "upcoming")
      assert_match "Préparer rayon", response.body
      assert_no_match(/Caisse ouvrante/, response.body)
      assert_no_match(/Vitrine à refaire/, response.body)
    end
  end

  test "area user sees open tasks across every store under them" do
    seed_task("Vitrine Maarif", store: @store)
    seed_task("Vitrine Rabat", store: @second_store)

    sign_in(@area_user)
    get inbox_index_path

    assert_response :success
    assert_match "Vitrine Maarif", response.body
    assert_match "Vitrine Rabat", response.body
    assert_select "span.task-list__store", text: "Maarif"
    assert_select "span.task-list__store", text: "Rabat"
  end

  test "store user still sees a task assigned to them in another store" do
    task = seed_task("Audit cross-store", store: @second_store)
    task.deliveries.find_by!(org_unit: @second_store).update!(assignee: @brand.store_user)

    sign_in(@brand.store_user)
    get inbox_index_path

    assert_response :success
    assert_match "Audit cross-store", response.body
    assert_select "span.task-list__badge", text: I18n.t("inbox.my_tasks.assigned_to_me", locale: :en)
  end

  test "my tasks hides finished tasks" do
    done_task = seed_task("Déjà bouclé", store: @store)
    done_task.deliveries.find_by!(org_unit: @store).update!(status: "completed", completed_at: Time.current)

    sign_in(@brand.store_user)
    get inbox_index_path

    assert_response :success
    assert_no_match(/Déjà bouclé/, response.body)
  end

  test "my_tasks route is an alias for the inbox index" do
    seed_task("Via alias", store: @store)
    sign_in(@brand.store_user)

    get my_tasks_path
    assert_response :success
    assert_match "Via alias", response.body
  end

  test "area user can view a task but cannot advance it" do
    task = seed_task("Vitrine Rabat", store: @second_store)
    delivery = task.deliveries.find_by!(org_unit: @second_store)

    sign_in(@area_user)
    get inbox_path(delivery)
    assert_response :success

    post advance_inbox_path(delivery), params: { step: "received" }
    assert_redirected_to inbox_path(delivery)
    assert_equal "pending", delivery.reload.awareness
  end

  test "unknown scope falls back to all" do
    seed_task("Scope fallback", store: @store)
    sign_in(@brand.store_user)

    get inbox_index_path(scope: "bogus")
    assert_response :success
    assert_match "Scope fallback", response.body
    assert_select "a.filter-chip.is-active", text: /#{Regexp.escape(I18n.t('inbox.my_tasks.filters.all', locale: :en))}/
  end

  private

  def seed_task(title_fr, store:, due_at: nil)
    brief = @tenant.communications.create!(
      author: @brand.hq,
      title_fr: title_fr,
      body_fr: "Body for #{title_fr}",
      format: "task",
      status: "draft",
      source: "compose",
      due_at: due_at
    )
    brief.send_to!([ store.id ])
    delivery = brief.deliveries.find_by!(org_unit: store)
    delivery.update!(due_at: due_at) if due_at
    brief
  end
end
