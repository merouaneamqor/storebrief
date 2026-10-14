require "test_helper"

class ChecklistItemResponseTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("atlas-evidence-model")
    template = @brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Ouverture",
      items: [ { title_fr: "Vitrine", requires_photo: true } ]
    )
    checklist = Checklist.build_from_template(template, author: @brand.hq)
    checklist.save!
    checklist.send_to!([ @brand.store.id ])
    @delivery = checklist.checklist_deliveries.first
    @item = checklist.checklist_items.first
  end

  test "accepts image evidence" do
    response = @delivery.checklist_item_responses.create!(checklist_item: @item, completed: true)
    response.photo.attach(
      io: file_fixture("window.jpg").open,
      filename: "window.jpg",
      content_type: "image/jpeg"
    )
    assert response.valid?
    assert response.evidence_image?
    assert_not response.evidence_video?
  end

  test "accepts short video evidence" do
    response = @delivery.checklist_item_responses.create!(checklist_item: @item, completed: true)
    response.photo.attach(
      io: StringIO.new("fake-mp4-bytes"),
      filename: "clip.mp4",
      content_type: "video/mp4"
    )
    assert response.valid?
    assert response.evidence_video?
  end

  test "rejects unsupported evidence types" do
    response = @delivery.checklist_item_responses.create!(checklist_item: @item, completed: true)
    response.photo.attach(
      io: StringIO.new("%PDF-1.4"),
      filename: "doc.pdf",
      content_type: "application/pdf"
    )
    assert_not response.valid?
    assert_includes response.errors[:photo], I18n.t("checklists.evidence_invalid")
  end
end
