require "test_helper"

class TaskDependenciesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("task-deps", features: { morocco_ops: true, briefs: true })
    @parent = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Installer la table",
      body_fr: "Mettre en place la table promo.",
      format: "task",
      status: "draft",
      source: "compose"
    )
    @parent.send_to!([ @brand.store.id ])
    @parent_delivery = @parent.deliveries.find_by!(org_unit: @brand.store)

    @child = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Photographier la table",
      body_fr: "Photo de preuve.",
      format: "task",
      status: "draft",
      source: "compose",
      depends_on_communication: @parent
    )
    @child.send_to!([ @brand.store.id ])
    @child_delivery = @child.deliveries.find_by!(org_unit: @brand.store)
  end

  test "dependent delivery stays blocked until parent is done" do
    assert @child_delivery.dependency_blocked?
    assert_match(/Installer la table/, @child_delivery.dependency_blocked_reason)

    error = assert_raises(ArgumentError) { @child_delivery.complete! }
    assert_match(/Installer la table/, error.message)

    @parent_delivery.complete!
    @child_delivery.reload
    assert_not @child_delivery.dependency_blocked?

    @child_delivery.complete!
    assert_equal "completed", @child_delivery.status
  end

  test "store UI shows blocked reason and rejects advance" do
    sign_in(@brand.store_user)

    get inbox_index_path
    assert_response :success
    assert_match I18n.t("morocco.dependency.blocked_badge", locale: :en), response.body
    assert_match(/Installer la table/, response.body)

    get inbox_path(@child_delivery)
    assert_response :success
    assert_match I18n.t("morocco.dependency.blocked_title", locale: :en), response.body
    assert_match(/Installer la table/, response.body)
    assert_no_match I18n.t("morocco.awareness.actions.received", locale: :en), response.body

    post advance_inbox_path(@child_delivery), params: { step: "received" }
    assert_redirected_to inbox_path(@child_delivery)
    follow_redirect!
    assert_match(/Installer la table/, flash[:alert].to_s + response.body)
    assert_equal "pending", @child_delivery.reload.awareness
  end

  test "hq can clear dependency for a store and reassign owner" do
    other = create_user(@brand.tenant, org_unit: @brand.store, role: :store, email: "other@task-deps.test")
    sign_in(@brand.hq)

    get communication_path(@child)
    assert_response :success
    assert_match I18n.t("morocco.dependency.title", locale: :en), response.body
    assert_match I18n.t("morocco.dependency.clear_store", locale: :en), response.body
    assert_match I18n.t("morocco.dependency.reassign", locale: :en), response.body

    post delivery_clear_dependency_path(@child_delivery)
    assert_redirected_to communication_path(@child)
    @child_delivery.reload
    assert_not @child_delivery.dependency_blocked?
    assert_not_nil @child_delivery.dependency_cleared_at
    assert_equal @brand.hq, @child_delivery.dependency_cleared_by

    patch delivery_reassign_path(@child_delivery), params: { assignee_id: other.id }
    assert_redirected_to communication_path(@child)
    assert_equal other, @child_delivery.reload.assignee
  end

  test "hq can clear the task-level dependency" do
    sign_in(@brand.hq)

    post clear_dependency_communication_path(@child)
    assert_redirected_to communication_path(@child)
    assert_nil @child.reload.depends_on_communication_id
    assert_not @child_delivery.reload.dependency_blocked?
  end

  test "store user cannot clear or reassign" do
    sign_in(@brand.store_user)

    post delivery_clear_dependency_path(@child_delivery)
    assert_redirected_to app_root_path
    assert @child_delivery.reload.dependency_blocked?

    patch delivery_reassign_path(@child_delivery), params: { assignee_id: @brand.store_user.id }
    assert_redirected_to app_root_path
  end
end
