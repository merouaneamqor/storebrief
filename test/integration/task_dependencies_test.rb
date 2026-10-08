require "test_helper"

class TaskDependenciesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("dependency-ui", features: { morocco_ops: true })
    @tenant = @brand.tenant
  end

  def send_task(title, depends_on: nil, format: "task")
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: title, body_fr: "Corps", format: format,
      status: "draft", depends_on: depends_on
    )
    brief.send_to!([ @brand.store.id ])
    brief
  end

  def delivery_for(brief)
    brief.deliveries.find_by(org_unit: @brand.store)
  end

  test "a dependent delivery stays blocked until the prerequisite is done" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon", depends_on: prereq)

    assert delivery_for(dependent).blocked?

    delivery_for(prereq).complete!
    assert_not delivery_for(dependent).reload.blocked?
  end

  test "completing a blocked task is refused" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon", depends_on: prereq)

    error = assert_raises(ArgumentError) { delivery_for(dependent).complete! }
    assert_match "Compter le stock", error.message
    assert delivery_for(dependent).reload.pending?
  end

  test "a blocked task cannot advance awareness" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon", depends_on: prereq)

    assert_raises(ArgumentError) { delivery_for(dependent).advance_awareness!("read") }
  end

  test "once the prerequisite is done the dependent completes" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon", depends_on: prereq)
    delivery_for(prereq).complete!

    delivery_for(dependent).complete!
    assert delivery_for(dependent).reload.finished?
  end

  test "no prerequisite delivery at the store means not blocked" do
    prereq = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Prérequis non envoyé", body_fr: "Corps", format: "task", status: "draft"
    )
    dependent = send_task("Réassort rayon", depends_on: prereq)

    assert_not delivery_for(dependent).blocked?
  end

  test "the store inbox shows a blocked reason and hides the action" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon", depends_on: prereq)
    sign_in @brand.store_user

    get inbox_index_path
    assert_select ".badge--blocked"

    get inbox_path(delivery_for(dependent))
    assert_response :success
    assert_select ".task-blocked"
    assert_select "form[action='#{complete_inbox_path(delivery_for(dependent))}']", count: 0
    assert_select "form[action='#{advance_inbox_path(delivery_for(dependent))}']", count: 0
  end

  test "the store cannot complete a blocked task through the inbox" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon", depends_on: prereq)
    sign_in @brand.store_user

    post complete_inbox_path(delivery_for(dependent))
    assert delivery_for(dependent).reload.pending?
  end

  test "HQ can set a prerequisite while composing" do
    prereq = send_task("Compter le stock")
    sign_in @brand.hq

    post communications_path, params: {
      communication: { title_fr: "Réassort", body_fr: "Corps", format: "task", depends_on_id: prereq.id },
      org_unit_ids: [ @brand.store.id ], commit: "send"
    }
    created = @tenant.communications.order(:id).last
    assert_equal prereq.id, created.depends_on_id
  end

  test "HQ can reassign and clear a prerequisite on a sent task" do
    first = send_task("Compter le stock")
    second = send_task("Nettoyer la réserve")
    dependent = send_task("Réassort rayon", depends_on: first)
    sign_in @brand.hq

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: second.id } }
    assert_redirected_to communication_path(dependent)
    assert_equal second.id, dependent.reload.depends_on_id

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: "" } }
    assert_nil dependent.reload.depends_on_id
  end

  test "a store user cannot change a dependency" do
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon")
    sign_in @brand.store_user

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: prereq.id } }
    assert_nil dependent.reload.depends_on_id
  end

  test "another tenant cannot change a dependency" do
    other = build_brand("dependency-other")
    prereq = send_task("Compter le stock")
    dependent = send_task("Réassort rayon")
    sign_in other.hq

    patch dependency_communication_path(dependent), params: { communication: { depends_on_id: prereq.id } }
    assert_response :not_found
    assert_nil dependent.reload.depends_on_id
  end

  test "a dependency must point at a task in the same tenant" do
    other = build_brand("dependency-foreign")
    foreign = other.tenant.communications.create!(
      author: other.hq, title_fr: "Étranger", body_fr: "Corps", format: "task", status: "draft"
    )
    dependent = @tenant.communications.new(
      author: @brand.hq, title_fr: "Réassort", body_fr: "Corps", format: "task", depends_on: foreign
    )
    assert_not dependent.valid?
  end

  test "a task cannot depend on itself" do
    dependent = send_task("Réassort rayon")
    dependent.depends_on_id = dependent.id
    assert_not dependent.valid?
  end

  test "a note never keeps a dependency" do
    prereq = send_task("Compter le stock")
    note = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Info", body_fr: "Corps", format: "news", depends_on: prereq
    )
    assert_nil note.depends_on_id
  end

  test "dependency labels exist in every locale" do
    %i[fr en es ar].each do |locale|
      %w[label none help summary save saved cleared invalid].each do |key|
        assert I18n.exists?("communications.dependency.#{key}", locale), "#{locale} #{key}"
      end
      %w[blocked blocked_reason].each do |key|
        assert I18n.exists?("inbox.#{key}", locale), "#{locale} inbox.#{key}"
      end
    end
  end
end
