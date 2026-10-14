require "test_helper"

class DeliveryCommentTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("comments-model", features: { morocco_ops: true, briefs: true, email_alerts: false, push_alerts: false, whatsapp_alerts: false })
    @brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Task", body_fr: "Body", format: "task", status: "draft"
    )
    @brief.send_to!([ @brand.store.id ])
    @delivery = @brief.deliveries.first
  end

  test "parses @email mentions and retains append-only audit event" do
    comment = @delivery.delivery_comments.create!(
      user: @brand.store_user,
      body: "Ping @#{@brand.hq.email} please"
    )

    assert_equal @brand.tenant.id, comment.tenant_id
    assert_includes comment.mentioned_user_ids, @brand.hq.id
    event = @delivery.delivery_events.find_by(kind: "comment")
    assert event
    assert_equal comment.id, event.payload["comment_id"]
    assert_equal @brand.store_user, event.actor

    assert_raises(ActiveRecord::ReadOnlyRecord) { comment.update!(body: "changed") }
  end

  test "threaded reply stays on same delivery" do
    root = @delivery.delivery_comments.create!(user: @brand.hq, body: "Root")
    reply = @delivery.delivery_comments.create!(user: @brand.store_user, body: "Reply", parent: root)
    assert_equal root.id, reply.parent_id

    other = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Other", body_fr: "X", format: "task", status: "draft"
    )
    other.send_to!([ @brand.store.id ])
    bad = other.deliveries.first.delivery_comments.new(user: @brand.hq, body: "Nope", parent: root)
    assert_not bad.valid?
  end
end
