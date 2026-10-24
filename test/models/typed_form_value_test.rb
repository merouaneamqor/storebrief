require "test_helper"

class TypedFormValueTest < ActiveSupport::TestCase
  test "validates numeric, calendar, rating and stable boolean values" do
    { "number" => [ "-2.75", "0", ".5" ], "date" => [ "2028-02-29" ], "rating" => %w[1 5], "yes_no_na" => %w[yes no na] }.each do |type, values|
      values.each { |value| assert TypedFormValue.valid?(type, value), "#{type}: #{value}" }
    end
    { "number" => %w[NaN Infinity 1abc], "date" => %w[2026-02-29 2026-13-01 22/10/2026], "rating" => %w[0 6 2.5], "yes_no_na" => %w[Oui unknown] }.each do |type, values|
      values.each { |value| assert_not TypedFormValue.valid?(type, value), "#{type}: #{value}" }
    end
  end

  test "legacy checklist defaults and typed metadata survive deployment" do
    brand = build_brand("typed-template")
    template = brand.tenant.checklist_templates.create!(category: "store_visit", title_fr: "Visite", items: ChecklistTemplate.normalize_items([
      { title_fr: "Legacy" }, { title_fr: "Note", question_type: "rating", weight: "2.5", required: true }
    ]))
    checklist = Checklist.build_from_template(template, author: brand.hq)
    assert_equal "short_text", checklist.checklist_items.first.question_type
    item = checklist.checklist_items.last
    assert_equal "rating", item.question_type
    assert_equal "2.5", item.metadata_hash[:weight]
    checklist.save!
    delivery = checklist.checklist_deliveries.create!(org_unit: brand.store)
    response = delivery.checklist_item_responses.build(checklist_item: item, completed: true, notes: "6")
    assert_not response.valid?
    response.notes = "5"
    assert response.valid?
  end
  test "template copies retain scoring weights and reject invalid weights" do
    brand = build_brand("typed-weights")
    template = brand.tenant.communication_templates.create!(title_fr: "Audit", body_fr: "", format: "task", questions: CommunicationTemplate.normalize_questions([
      { title_fr: "OK", question_type: "yes_no_na", weight: "3.25" }
    ]))
    brief = Communication.build_from_template(template, author: brand.hq)
    assert_equal 3.25, brief.communication_questions.first.weight
    brief.save!
    copy = CommunicationTemplate.from_communication(brief)
    assert_equal 3.25, copy.question_defs.first[:weight].to_d
    question = brief.communication_questions.first
    [ 0, -1, "invalid" ].each do |weight|
      question.weight = weight
      assert_not question.valid?
    end
    template.questions = [ { title_fr: "Bad", weight: -1 } ]
    assert_not template.valid?
  end
end
