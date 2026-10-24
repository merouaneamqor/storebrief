require "test_helper"

class TaskExecutionPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("execution-ux", features: { morocco_ops: true })
    @task = send_brief("Required work", format: "task")
    @delivery = @task.deliveries.first
    @news = send_brief("Read only news", format: "news")
    @news_delivery = @news.deliveries.first
    @role = @brand.tenant.tenant_roles.create!(name: "Read only", base_role: "store", capabilities: [ "inbox" ])
    @brand.store_user.memberships.first.update!(tenant_role: @role)
    sign_in(@brand.store_user)
  end

  test "inbox-only store can read task and news but cannot mutate task execution" do
    get inbox_index_path
    assert_response :success
    assert_select "a[href='#{inbox_path(@delivery)}']"
    assert_select "a[href='#{inbox_path(@news_delivery)}']"
    %w[fr ar en es].each do |locale|
      get inbox_path(@delivery, locale: locale)
      assert_response :success
      assert_select "form.task-card__action", count: 0
      assert_select "p[role=status]", text: I18n.t("store_work.execution_not_allowed", locale: locale)
    end
    initial_awareness = @delivery.awareness
    [ complete_inbox_path(@delivery), advance_inbox_path(@delivery) ].each do |target|
      assert_no_difference [ "DeliveryEvent.count", "ActiveStorage::Attachment.count" ] do
        post target, params: { step: "received", proof_files: [ fixture_file_upload("notes.txt", "text/plain") ], proof_request_id: "unauthorized" }, headers: { "Accept" => "application/json" }
      end
      assert_response :forbidden
      assert_equal "pending", @delivery.reload.status
      assert_equal initial_awareness, @delivery.awareness
    end
    post complete_inbox_path(@delivery)
    assert_redirected_to inbox_path(@delivery)
    assert_equal I18n.t("store_work.execution_not_allowed", locale: :es), flash[:alert]

    get inbox_path(@news_delivery)
    assert_response :success
    post advance_inbox_path(@news_delivery), params: { step: "received" }
    assert_redirected_to inbox_path(@news_delivery)
    post complete_inbox_path(@news_delivery)
    assert_equal "read", @news_delivery.reload.status
  end

  test "execute-only store follows My Tasks to task execution but cannot read or acknowledge news" do
    @role.update!(capabilities: [ "execute" ])
    get my_task_path(@delivery, kind: "task")
    assert_response :success
    assert_select "a[href='#{inbox_path(@delivery)}']"
    get inbox_index_path
    assert_response :success
    assert_select "a[href='#{inbox_path(@delivery)}']"
    assert_select "a[href='#{inbox_path(@news_delivery)}']", count: 0
    get inbox_path(@delivery)
    assert_response :success
    assert_select "form.task-card__action"
    post advance_inbox_path(@delivery), params: { step: "received" }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "received", @delivery.reload.awareness
    post complete_inbox_path(@delivery), headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "completed", @delivery.reload.status

    get inbox_path(@news_delivery)
    assert_response :not_found
    [ complete_inbox_path(@news_delivery), advance_inbox_path(@news_delivery) ].each do |target|
      post target, params: { step: "received" }, headers: { "Accept" => "application/json" }
      assert_response :not_found
    end
    assert_equal "pending", @news_delivery.reload.status

    broadcast = send_brief("Critical notice", format: "announcement", critical_broadcast: true, requires_acknowledgement: true)
    post broadcast_acknowledgement_path(broadcast.deliveries.first)
    assert_redirected_to app_root_path
    assert_nil broadcast.deliveries.first.reload.acknowledged_at
  end

  test "no-capability role is denied at every inbox action" do
    @role.update!(capabilities: [])
    [ inbox_index_path, inbox_path(@delivery) ].each do |target|
      get target
      assert_redirected_to app_root_path
    end
    [ complete_inbox_path(@delivery), advance_inbox_path(@delivery) ].each do |target|
      post target, params: { step: "received" }, headers: { "Accept" => "application/json" }
      assert_response :forbidden
    end
    assert_equal "pending", @delivery.reload.status
  end

  test "all custom store capabilities retain own-store and own-tenant scope" do
    other_store = @brand.tenant.org_units.create!(name: "Other store", unit_type: "store", parent: @brand.region)
    other_delivery = @task.deliveries.create!(org_unit: other_store, status: "pending")
    foreign = build_brand("execution-foreign")
    foreign_task = foreign.tenant.communications.create!(author: foreign.hq, title_fr: "Foreign", body_fr: "Private", format: "task", status: "draft")
    foreign_task.send_to!([ foreign.store.id ])
    [ %w[inbox], %w[execute], %w[inbox execute] ].each do |caps|
      @role.update!(capabilities: caps)
      [ other_delivery, foreign_task.deliveries.first ].each do |delivery|
        get inbox_path(delivery)
        assert_response :not_found
        [ complete_inbox_path(delivery), advance_inbox_path(delivery) ].each do |target|
          post target, params: { step: "received" }, headers: { "Accept" => "application/json" }
          assert_response :not_found
        end
        assert_equal "pending", delivery.reload.status
      end
    end
  end

  test "HQ and area still cannot use store inbox actions" do
    area = create_user(@brand.tenant, org_unit: @brand.region, role: :area, email: "area@execution-ux.test")
    [ @brand.hq, area ].each do |user|
      sign_in(user)
      [ inbox_index_path, inbox_path(@delivery) ].each do |target|
        get target
        assert_redirected_to app_root_path
      end
      [ complete_inbox_path(@delivery), advance_inbox_path(@delivery) ].each do |target|
        post target, params: { step: "received" }
        assert_redirected_to app_root_path
      end
    end
    assert_equal "pending", @delivery.reload.status
  end

  test "legacy non-Morocco task forms also respect execution permission" do
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    get inbox_path(@delivery)
    assert_response :success
    assert_select "form.brief-answer-form", count: 0
    post complete_inbox_path(@delivery), headers: { "Accept" => "application/json" }
    assert_response :forbidden
    assert_equal "pending", @delivery.reload.status
  end

  private

  def send_brief(title, **attributes)
    brief = @brand.tenant.communications.create!({ author: @brand.hq, title_fr: title, body_fr: "Instructions", status: "draft" }.merge(attributes))
    brief.send_to!([ @brand.store.id ])
    brief
  end
end
