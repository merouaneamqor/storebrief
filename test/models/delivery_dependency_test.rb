require "test_helper"

class DeliveryDependencyTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("dep-model", features: { morocco_ops: true, briefs: true })
    @parent = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Parent task",
      body_fr: "Do this first.",
      format: "task",
      status: "draft",
      source: "compose"
    )
    @parent.send_to!([ @brand.store.id ])
    @child = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Child task",
      body_fr: "Do this second.",
      format: "task",
      status: "draft",
      source: "compose",
      depends_on_communication: @parent
    )
    @child.send_to!([ @brand.store.id ])
    @delivery = @child.deliveries.first
  end

  test "communication rejects self dependency and news parent" do
    assert_not @child.update(depends_on_communication: @child)

    note = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Note",
      body_fr: "Info",
      format: "news",
      status: "draft",
      source: "compose"
    )
    note.send_to!([ @brand.store.id ])
    assert_not @child.update(depends_on_communication: note)
  end

  test "clearing dependency block unlocks the delivery" do
    assert @delivery.dependency_blocked?
    @delivery.clear_dependency_block!(by: @brand.hq)
    assert_not @delivery.dependency_blocked?
    assert_equal "dependency_cleared", @delivery.delivery_events.order(:id).last.kind
  end
end
