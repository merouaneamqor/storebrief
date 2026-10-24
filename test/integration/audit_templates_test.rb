require "test_helper"

class AuditTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("atlas-audit-templates")
  end

  test "hq creates edits and deletes an audit template with sections and questions" do
    sign_in(@brand.hq)

    get new_template_path
    assert_response :success

    assert_difference -> { @brand.tenant.checklist_templates.count }, 1 do
      post templates_path, params: {
        checklist_template: {
          category: "store_visit",
          title_fr: "Audit rayon",
          title_ar: "تدقيق الرف",
          description_fr: "Visite merchandising",
          items: {
            "0" => { type: "section", key: "merch", title_fr: "Merchandising", title_ar: "العرض" },
            "1" => {
              type: "question", key: "facing", title_fr: "Facing correct", title_ar: "الواجهة صحيحة",
              required: "1", requires_photo: "0"
            },
            "2" => {
              type: "question", key: "photo_plv", title_fr: "Photo PLV", title_ar: "صورة العرض",
              required: "0", requires_photo: "1",
              show_if: { question_key: "facing", equals: "non" }
            }
          }
        }
      }
    end

    template = @brand.tenant.checklist_templates.order(:id).last
    assert_redirected_to templates_path
    assert_equal "Audit rayon", template.title_fr
    assert_equal 2, template.question_count
    assert_equal "section", template.item_defs.first[:type]
    photo = template.question_defs.find { |q| q[:key] == "photo_plv" }
    assert_equal({ "question_key" => "facing", "equals" => "non" }, photo[:show_if].stringify_keys)

    get edit_template_path(template)
    assert_response :success

    patch template_path(template), params: {
      checklist_template: {
        category: "store_visit",
        title_fr: "Audit rayon v2",
        title_ar: "تدقيق الرف",
        description_fr: "Visite merchandising",
        items: {
          "0" => { type: "section", key: "merch", title_fr: "Merchandising", title_ar: "العرض" },
          "1" => {
            type: "question", key: "facing", title_fr: "Facing OK", title_ar: "الواجهة صحيحة",
            required: "1", requires_photo: "0"
          }
        }
      }
    }
    assert_redirected_to templates_path
    assert_equal "Audit rayon v2", template.reload.title_fr
    assert_equal 1, template.question_count

    assert_difference -> { @brand.tenant.checklist_templates.count }, -1 do
      delete template_path(template)
    end
    assert_redirected_to templates_path
  end

  test "rejects duplicate question keys" do
    sign_in(@brand.hq)

    assert_no_difference -> { @brand.tenant.checklist_templates.count } do
      post templates_path, params: {
        checklist_template: {
          category: "opening",
          title_fr: "Doublon",
          items: {
            "0" => { type: "question", key: "same", title_fr: "Q1", required: "0", requires_photo: "0" },
            "1" => { type: "question", key: "same", title_fr: "Q2", required: "0", requires_photo: "0" }
          }
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "build_from_template flattens questions with required and show_if metadata" do
    template = @brand.tenant.checklist_templates.create!(
      category: "store_visit",
      title_fr: "Visite",
      items: [
        { "type" => "section", "key" => "sec", "title_fr" => "Section A" },
        {
          "type" => "question", "key" => "q1", "title_fr" => "Obligatoire",
          "required" => true, "requires_photo" => false
        },
        {
          "type" => "question", "key" => "q2", "title_fr" => "Conditionnelle",
          "required" => false, "requires_photo" => true,
          "show_if" => { "question_key" => "q1", "equals" => "oui" }
        }
      ]
    )

    checklist = Checklist.build_from_template(template, author: @brand.hq)
    checklist.save!

    assert_equal 2, checklist.checklist_items.count
    first, second = checklist.checklist_items.to_a
    assert first.required?
    assert_equal "q1", first.template_key
    assert_not second.required?
    assert second.requires_photo?
    assert_equal({ "question_key" => "q1", "equals" => "oui" }, second.show_if.stringify_keys)
  end

  test "legacy flat items still build checklist items" do
    template = @brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Legacy",
      items: [
        { "title_fr" => "Alarme", "requires_photo" => false },
        { "title_fr" => "Vitrine", "requires_photo" => true }
      ]
    )

    checklist = Checklist.build_from_template(template, author: @brand.hq)
    checklist.save!
    assert_equal [ "Alarme", "Vitrine" ], checklist.checklist_items.map(&:title_fr)
    assert_equal [ false, false ], checklist.checklist_items.map(&:required)
  end

  test "templates are tenant scoped" do
    other = build_brand("contoso-audit-templates")
    foreign = other.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Autre tenant",
      items: [ { "type" => "question", "key" => "x", "title_fr" => "Q", "required" => false } ]
    )

    sign_in(@brand.hq)
    get edit_template_path(foreign)
    assert_response :not_found

    patch template_path(foreign), params: {
      checklist_template: { title_fr: "Hack", category: "opening", items: [] }
    }
    assert_response :not_found

    delete template_path(foreign)
    assert_response :not_found
    assert foreign.reload.persisted?
  end

  test "store users cannot manage templates" do
    sign_in(@brand.store_user)
    get new_template_path
    assert_redirected_to app_root_path
  end
end
