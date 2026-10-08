require "test_helper"

class TaskDependenciesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("dependency-ui", features: { morocco_ops: true })
    @tenant = @brand.tenant
  end

  def build_task(title, depends_on: nil, format: "task")
    @tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Corps", format: format,
      status: "draft", depends_on: depends_on
    )
  end

  def send_task(title, depends_on: nil)
    brief = build_task(title, depends_on: depends_on)
    brief.send_to!([ @brand.store.id ])
    brief
  end

  test "a dependent delivery stays blocked until the prerequisite is done" do
    prerequisite = send_task("Ranger la reserve")
    dependent = send_task("Monter la PLV", depends_on: prerequisite)
    delivery = dependent.deliveries.first

    assert delivery.blocked?
    assert_raises(ArgumentError) { delivery.complete! }
    assert_raises(ArgumentError) { delivery.advance_awareness!("received") }
    assert_equal "pending", delivery.reload.status

    prerequisite.deliveries.first.complete!
    assert_not delivery.blocked?
    delivery.complete!
    assert_equal "completed", delivery.reload.status
  end

  test "a prerequisite still in draft blocks the dependent task" do
    prerequisite = build_task("Brief a venir")
    dependent = send_task("Suite", depends_on: prerequisite)

    assert dependent.deliveries.first.blocked?
  end

  test "a store that never received the prerequisite is not blocked" do
    other_store = @tenant.org_units.create!(name: "Gueliz", unit_type: "store", parent: @brand.region)
    prerequisite = build_task("Cible partielle")
    prerequisite.send_to!([ other_store.id ])
    dependent = send_task("Pour tous", depends_on: prerequisite)

    assert_not dependent.deliveries.first.blocked?
  end

  test "dependency rejects self reference, cycles, news, and other tenants" do
    task_a = send_task("A")
    task_b = send_task("B", depends_on: task_a)

    task_a.depends_on = task_a
    assert_not task_a.valid?

    task_a.depends_on = task_b
    assert_not task_a.valid?

    note = build_task("Note", format: "news")
    task_c = @tenant.communications.new(
      author: @brand.hq, title_fr: "C", body_fr: "Corps", format: "task", depends_on: note
    )
    assert_not task_c.valid?

    other = build_brand("dependency-other")
    foreign = other.tenant.communications.create!(
      author: other.hq, title_fr: "Ailleurs", body_fr: "Corps", format: "task"
    )
    task_d = @tenant.communications.new(
      author: @brand.hq, title_fr: "D", body_fr: "Corps", format: "task", depends_on: foreign
    )
    assert_not task_d.valid?
  end

  test "a note never keeps a dependency" do
    prerequisite = send_task("Avant")
    note = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Info", body_fr: "Corps", format: "news", depends_on: prerequisite
    )
    assert_nil note.depends_on_id
  end

  test "the store inbox shows the blocked reason and hides the action" do
    prerequisite = send_task("Nettoyer la vitrine")
    dependent = send_task("Installer la promo", depends_on: prerequisite)
    sign_in @brand.store_user

    get inbox_path(dependent.deliveries.first)
    assert_response :success
    assert_select ".blocked-note", text: /Nettoyer la vitrine/
    assert_select ".sticky-action", count: 0

    get inbox_index_path
    assert_select ".badge--blocked"
  end

  test "a store cannot complete a blocked task over HTTP" do
    prerequisite = send_task("Avant tout")
    dependent = send_task("Bloquee", depends_on: prerequisite)
    delivery = dependent.deliveries.first
    sign_in @brand.store_user

    post advance_inbox_path(delivery), params: { step: "received" }
    assert_redirected_to inbox_path(delivery)
    assert_equal "pending", delivery.reload.awareness
    assert_equal "pending", delivery.status
    assert_nil delivery.completed_at

    post complete_inbox_path(delivery)
    assert_equal "pending", delivery.reload.status
  end

  test "HQ composes a task with a dependency" do
    prerequisite = send_task("Etape 1")
    sign_in @brand.hq

    post communications_path, params: {
      communication: { title_fr: "Etape 2", body_fr: "Corps", format: "task", depends_on_id: prerequisite.id },
      org_unit_ids: [ @brand.store.id ], commit: "send"
    }
    assert_equal prerequisite.id, @tenant.communications.order(:id).last.depends_on_id
  end

  test "the editor offers dependency choices for tasks" do
    send_task("Candidate")
    sign_in @brand.hq

    get new_communication_path
    assert_select "select[name='communication[depends_on_id]'] option", minimum: 2
  end

  test "HQ can reassign and clear a dependency on a sent task" do
    first = send_task("Un")
    second = send_task("Deux")
    dependent = send_task("Trois", depends_on: first)
    sign_in @brand.hq

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: second.id } }
    assert_redirected_to communication_path(dependent)
    assert_equal second.id, dependent.reload.depends_on_id

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: "" } }
    assert_nil dependent.reload.depends_on_id
    assert_not dependent.deliveries.first.blocked?
  end

  test "a store user cannot change a dependency" do
    prerequisite = send_task("Avant")
    dependent = send_task("Apres", depends_on: prerequisite)
    sign_in @brand.store_user

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: "" } }
    assert_equal prerequisite.id, dependent.reload.depends_on_id
  end

  test "another tenant cannot change or use a dependency" do
    prerequisite = send_task("Avant")
    dependent = send_task("Apres", depends_on: prerequisite)
    other = build_brand("dependency-intrus")
    sign_in other.hq

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: "" } }
    assert_response :not_found
    assert_equal prerequisite.id, dependent.reload.depends_on_id
  end

  test "dependency labels exist in every locale" do
    %i[fr en es ar].each do |locale|
      %w[title label help none save saved cleared invalid].each do |key|
        assert I18n.exists?("communications.dependency.#{key}", locale), "#{locale} #{key}"
      end
      %w[blocked blocked_by].each do |key|
        assert I18n.exists?("inbox.#{key}", locale), "#{locale} #{key}"
      end
    end
  end
end
