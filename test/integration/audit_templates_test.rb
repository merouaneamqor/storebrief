require "test_helper"

class AuditTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("audit-ui", features: { morocco_ops: true })
    @area = @brand.tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @area_user = create_user(@brand.tenant, org_unit: @area, role: :area, email: "area@audit-ui.test")
  end

  test "hq builds a questionnaire with a required and a conditional question" do
    sign_in(@brand.hq)
    get new_audit_template_path
    assert_response :success
    assert_select "[x-data='auditTemplateForm']"

    assert_difference -> { @brand.tenant.audit_templates.count }, 1 do
      post audit_templates_path, params: { audit_template: template_params }
    end
    template = @brand.tenant.audit_templates.last
    assert_redirected_to audit_template_path(template)
    assert_equal "q1", template.questions.first["key"]
    assert template.questions.first["required"]
    assert_equal "q1", template.questions.last["show_if_key"]
    assert_equal "non_conforme", template.questions.last["show_if_value"]

    follow_redirect!
    assert_match "Pourquoi", response.body
    assert_match I18n.t("morocco.audit_templates.shown_when", locale: :en, key: "q1", value: "non_conforme"), response.body
  end

  test "a condition that points nowhere is rejected" do
    sign_in(@brand.hq)
    params = template_params
    params[:sections]["0"][:questions]["1"][:show_if_key] = "nope"
    assert_no_difference -> { AuditTemplate.count } do
      post audit_templates_path, params: { audit_template: params }
    end
    assert_response :unprocessable_entity
  end

  test "store users cannot open questionnaires and another tenant stays hidden" do
    template = save_template
    other = build_brand("audit-foreign", features: { morocco_ops: true })
    foreign = other.tenant.audit_templates.create!(title_fr: "Secret", sections: template.sections)

    sign_in(@brand.store_user)
    get audit_templates_path
    assert_redirected_to app_root_path

    delete logout_path
    sign_in(@area_user)
    get audit_templates_path
    assert_response :success
    assert_match template.title, response.body
    assert_no_match "Secret", response.body
    get audit_template_path(foreign)
    assert_response :not_found
  end

  test "a visit can use a tenant questionnaire and ignores a foreign one" do
    template = save_template
    foreign = build_brand("audit-visit", features: { morocco_ops: true }).tenant.audit_templates.create!(
      title_fr: "Ailleurs", sections: template.sections
    )
    sign_in(@brand.hq)

    post visits_path, params: { visit: {
      org_unit_id: @brand.store.id, auditor_id: @brand.hq.id,
      planned_at: "2026-11-02T10:30", audit_template_id: template.id
    } }
    visit = @brand.tenant.visits.order(:id).last
    assert_equal template, visit.audit_template

    post visits_path, params: { visit: {
      org_unit_id: @brand.store.id, auditor_id: @brand.hq.id,
      planned_at: "2026-11-03T10:30", audit_template_id: foreign.id
    } }
    assert_nil @brand.tenant.visits.order(:id).last.audit_template
  end

  test "copy exists in every locale without em dashes" do
    %i[fr en es ar].each do |locale|
      copy = I18n.t("morocco.audit_templates.title", locale: locale)
      assert copy.present?
      assert_not copy.include?("—")
    end
  end

  private

  def template_params
    {
      title_fr: "Vitrine",
      title_ar: "واجهة",
      description_fr: "Contrôle du matin",
      sections: {
        "0" => {
          key: "s1",
          title_fr: "Devanture",
          questions: {
            "0" => { key: "q1", prompt_fr: "Vitrine propre", kind: "verdict", required: "1", points: "2" },
            "1" => { key: "q2", prompt_fr: "Pourquoi", kind: "text", required: "0", points: "0",
                     show_if_key: "q1", show_if_value: "non_conforme" }
          }
        }
      }
    }
  end

  def save_template
    @brand.tenant.audit_templates.create!(
      title_fr: "Vitrine",
      sections: AuditTemplate.normalize_sections(template_params[:sections])
    )
  end
end
