require "test_helper"

class ChecklistReviewsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("checklist-review", features: { push_alerts: false })
    @area = @brand.tenant.org_units.create!(name: "Area", unit_type: "area", parent: @brand.region)
    @brand.store.update!(parent: @area)
    @manager = create_user(@brand.tenant, org_unit: @area, role: "area")
    @checklist = @brand.tenant.checklists.create!(author: @brand.hq, title_fr: "Audit checklist", status: "sent")
    @item = @checklist.checklist_items.create!(title_fr: "Temperature", required: true, metadata: { question_type: "number" })
    @delivery = @checklist.checklist_deliveries.create!(org_unit: @brand.store, status: "completed", completed_at: Time.current)
    @item_response = @delivery.checklist_item_responses.create!(checklist_item: @item, completed: true, notes: "10")
  end

  test "HQ verdict reopens responses without losing evidence and records append-only history" do
    sign_in @brand.hq
    post verdict_checklist_review_path(@delivery), params: { verdict: "non_conforme", verdict_note: "Correct the temperature" }
    assert_redirected_to checklist_review_path(@delivery)
    assert_equal "non_conforme", @delivery.reload.verdict
    assert_equal "pending", @delivery.status
    assert_nil @delivery.completed_at
    assert_equal @brand.hq, @delivery.validated_by
    assert_not @item_response.reload.completed?
    assert_equal "10", @item_response.notes
    assert_equal %w[status verdict], @delivery.checklist_delivery_events.pluck(:kind)
    event = @delivery.checklist_delivery_events.last
    assert_equal @brand.hq, event.actor
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(kind: "comment") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy! }
    sign_in @brand.store_user
    post submit_item_checklists_delivery_path(@delivery), params: { item_id: @item.id, notes: "8" }
    assert_equal "completed", @delivery.reload.status
    assert_equal "status", @delivery.checklist_delivery_events.last.kind
  end

  test "area review scope excludes sibling and foreign stores" do
    sibling = @brand.tenant.org_units.create!(name: "Hidden store", unit_type: "store", parent: @brand.region)
    hidden = @checklist.checklist_deliveries.create!(org_unit: sibling, status: "pending")
    sign_in @manager
    get checklist_reviews_path
    assert_select "a[href=?]", checklist_review_path(@delivery), count: 1
    assert_select "a[href=?]", checklist_review_path(hidden), count: 0
    get checklist_review_path(hidden)
    assert_response :not_found
    assert_no_difference "ChecklistDeliveryEvent.count" do
      post verdict_checklist_review_path(hidden), params: { verdict: "conforme" }
      assert_response :not_found
    end
    post verdict_checklist_review_path(@delivery), params: { verdict: "conforme" }
    assert_equal "conforme", @delivery.reload.verdict
    outsider = build_brand("other-review")
    sign_in outsider.hq
    get checklist_review_path(@delivery)
    assert_response :not_found
  end

  test "store can discuss its own delivery with threaded mentions but cannot issue verdicts" do
    sign_in @brand.store_user
    assert_no_difference "NotificationLog.count" do
      post comment_checklist_review_path(@delivery), params: { checklist_delivery_comment: { body: "Please review @#{@manager.email}" } }
    end
    assert_redirected_to "#{checklists_delivery_path(@delivery)}#comments"
    root = @delivery.checklist_delivery_comments.last
    assert_equal [ @manager.id ], root.mentioned_user_ids
    sign_in @manager
    post comment_checklist_review_path(@delivery), params: { checklist_delivery_comment: { body: "Recheck the fridge", parent_id: root.id } }
    assert_equal root.id, @delivery.checklist_delivery_comments.last.parent_id
    assert_equal 2, @delivery.checklist_delivery_events.where(kind: "comment").count
    sign_in @brand.store_user
    get checklists_delivery_path(@delivery)
    assert_response :success
    assert_select "#comments", text: /Recheck the fridge/
    assert_select "form[action=?]", verdict_checklist_review_path(@delivery), count: 0
    assert_no_difference "ChecklistDeliveryEvent.count" do
      post verdict_checklist_review_path(@delivery), params: { verdict: "conforme" }
      assert_redirected_to app_root_path
    end
    assert_raises(ActiveRecord::ReadOnlyRecord) { root.update!(body: "Changed") }
  end

  test "mentions and parent references cannot cross view scope or tenant" do
    sibling = @brand.tenant.org_units.create!(name: "Private store", unit_type: "store", parent: @brand.region)
    hidden_user = create_user(@brand.tenant, org_unit: sibling, role: "store", email: "hidden@checklist-review.test")
    foreign = build_brand("foreign-review")
    sign_in @brand.store_user
    post comment_checklist_review_path(@delivery), params: { checklist_delivery_comment: {
      body: "@#{hidden_user.email} @#{foreign.hq.email}", mentioned_user_ids: [ hidden_user.id, foreign.hq.id, @brand.hq.id ]
    } }
    comment = @delivery.checklist_delivery_comments.last
    assert_equal [ @brand.hq.id ], comment.mentioned_user_ids
    hidden_delivery = @checklist.checklist_deliveries.create!(org_unit: sibling, status: "pending")
    parent = hidden_delivery.checklist_delivery_comments.create!(tenant: @brand.tenant, user: @brand.hq, body: "Private thread")
    assert_no_difference "ChecklistDeliveryComment.count" do
      post comment_checklist_review_path(@delivery), params: { checklist_delivery_comment: { body: "Invalid reply", parent_id: parent.id } }
    end
    post comment_checklist_review_path(hidden_delivery), params: { checklist_delivery_comment: { body: "Forbidden" } }
    assert_response :not_found
  end

  test "custom monitor role can read but cannot verdict and removed execute forbids comments" do
    role = @brand.tenant.tenant_roles.create!(name: "Reader", base_role: "area", capabilities: [ "monitor" ])
    @manager.memberships.first.update!(tenant_role: role)
    sign_in @manager
    get checklist_review_path(@delivery)
    assert_response :success
    assert_select "form[action=?]", verdict_checklist_review_path(@delivery), count: 0
    assert_no_difference "ChecklistDeliveryEvent.count" do
      post verdict_checklist_review_path(@delivery), params: { verdict: "conforme" }
      assert_redirected_to app_root_path
    end
    store_role = @brand.tenant.tenant_roles.create!(name: "Inbox only", base_role: "store", capabilities: [ "inbox" ])
    @brand.store_user.memberships.first.update!(tenant_role: store_role)
    sign_in @brand.store_user
    post comment_checklist_review_path(@delivery), params: { checklist_delivery_comment: { body: "Denied" } }
    assert_response :not_found
  end

  test "feature gates, invalid verdicts and four locale views" do
    sign_in @brand.hq
    assert_no_difference "ChecklistDeliveryEvent.count" do
      post verdict_checklist_review_path(@delivery), params: { verdict: "invalid" }
    end
    %w[fr ar en es].each do |locale|
      @brand.hq.update!(locale: locale)
      get checklist_review_path(@delivery)
      assert_response :success
      assert_no_match(/translation missing|Translation missing/, response.body)
    end
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    get checklist_reviews_path
    assert_redirected_to app_root_path
  end
end
