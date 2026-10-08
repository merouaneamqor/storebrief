require "test_helper"

class AuditTemplateTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("audit-model", features: { morocco_ops: true })
  end

  test "requires a section and rejects a dangling condition" do
    template = @brand.tenant.audit_templates.new(title_fr: "Vitrine", sections: [])
    assert_not template.valid?

    template.sections = AuditTemplate.normalize_sections([
      {
        title_fr: "Devanture",
        questions: [
          { key: "q1", prompt_fr: "Vitrine propre", kind: "verdict", required: true, points: 2 },
          { key: "q2", prompt_fr: "Pourquoi", kind: "text", show_if_key: "missing", show_if_value: "non_conforme" }
        ]
      }
    ])
    assert_not template.valid?

    template.sections.last["questions"].last["show_if_key"] = "q1"
    assert template.valid?
    assert_equal 2, template.max_points
    assert template.question_visible?(template.questions.last, { "q1" => "non_conforme" })
    assert_not template.question_visible?(template.questions.last, { "q1" => "conforme" })
  end

  test "question keys must be unique across sections" do
    template = @brand.tenant.audit_templates.new(
      title_fr: "Vitrine",
      sections: [
        {
          "key" => "s1", "title_fr" => "Devanture",
          "questions" => [
            { "key" => "q1", "prompt_fr" => "Propre", "kind" => "verdict", "required" => true, "points" => 1 }
          ]
        },
        {
          "key" => "s2", "title_fr" => "Reserve",
          "questions" => [
            { "key" => "q1", "prompt_fr" => "Stock", "kind" => "yes_no", "required" => true, "points" => 1 }
          ]
        }
      ]
    )
    assert_not template.valid?

    template.sections.last["questions"].first["key"] = "q2"
    assert template.valid?
  end

  test "a template cannot be attached to another tenant visit" do
    template = @brand.tenant.audit_templates.create!(
      title_fr: "Vitrine",
      sections: [ { "key" => "s1", "title_fr" => "Devanture", "questions" => [
        { "key" => "q1", "prompt_fr" => "Propre", "kind" => "verdict", "required" => true, "points" => 1 }
      ] } ]
    )
    other = build_brand("audit-other")
    visit = other.tenant.visits.new(
      org_unit: other.store, auditor: other.hq, planned_at: 1.day.from_now, audit_template: template
    )
    assert_not visit.valid?
  end
end
