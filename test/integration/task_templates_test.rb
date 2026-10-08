require "test_helper"

class TaskTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("template-ui", features: { morocco_ops: true })
    @tenant = @brand.tenant
  end

  def create_brief(title, requires_proof: false)
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: title, title_ar: "عنوان", body_fr: "Corps", body_ar: "نص",
      format: "task", status: "draft", priority: "important", requires_proof: requires_proof
    )
    brief.communication_questions.create!(
      position: 0, question_type: "single_choice", title_fr: "Rayon pret ?", required: true,
      options: [ { "label_fr" => "Oui", "label_ar" => "نعم" }, { "label_fr" => "Non", "label_ar" => "لا" } ]
    )
    brief.communication_questions.create!(
      position: 1, question_type: "short_text", title_fr: "Commentaire"
    )
    brief
  end

  test "HQ saves a brief as a template with its questions, proof flag, and priority" do
    brief = create_brief("Lancement promo", requires_proof: true)
    brief.send_to!([ @brand.store.id ])
    sign_in @brand.hq

    assert_difference "BriefTemplate.count", 1 do
      post save_template_communication_path(brief), params: { template_name: "Promo type" }
    end
    assert_redirected_to brief_templates_path

    template = @tenant.brief_templates.last
    assert_equal "Promo type", template.name
    assert_equal "Lancement promo", template.title_fr
    assert_equal "important", template.priority
    assert template.requires_proof?
    assert_equal %w[single_choice short_text], template.question_defs.map { |q| q[:question_type] }
    assert_equal [ "Oui", "Non" ], template.question_defs.first[:options].map { |o| o["label_fr"] }
  end

  test "the template name defaults to the brief title" do
    brief = create_brief("Sans nom")
    sign_in @brand.hq

    post save_template_communication_path(brief)
    assert_equal "Sans nom", @tenant.brief_templates.last.name
  end

  test "using a template creates a fresh draft ready for targeting" do
    template = BriefTemplate.capture!(create_brief("Reutilisable"))
    sign_in @brand.hq

    assert_difference "@tenant.communications.count", 1 do
      post use_brief_template_path(template)
    end
    draft = @tenant.communications.order(:id).last
    assert_redirected_to edit_communication_path(draft)
    assert draft.draft?
    assert_equal "Reutilisable", draft.title_fr
    assert_equal "important", draft.priority
    assert_equal 2, draft.communication_questions.count
    assert draft.communication_questions.ordered.first.required?
  end

  test "a draft created from a template deploys to targets" do
    template = BriefTemplate.capture!(create_brief("A deployer"))
    sign_in @brand.hq

    post use_brief_template_path(template)
    draft = @tenant.communications.order(:id).last
    post send_brief_communication_path(draft), params: { org_unit_ids: [ @brand.store.id ] }

    assert draft.reload.sent?
    assert_equal [ @brand.store.id ], draft.deliveries.pluck(:org_unit_id)
  end

  test "the library lists only the tenant's templates" do
    BriefTemplate.capture!(create_brief("La notre"))
    other = build_brand("template-other")
    other.tenant.brief_templates.create!(name: "Ailleurs", title_fr: "Ailleurs", body_fr: "Corps")
    sign_in @brand.hq

    get brief_templates_path
    assert_response :success
    assert_select "li strong", text: "La notre"
    assert_select "li strong", text: "Ailleurs", count: 0
  end

  test "another tenant cannot use or delete a template" do
    template = BriefTemplate.capture!(create_brief("Protege"))
    other = build_brand("template-intrus")
    sign_in other.hq

    post use_brief_template_path(template)
    assert_response :not_found

    delete brief_template_path(template)
    assert_response :not_found
    assert BriefTemplate.exists?(template.id)
  end

  test "a store user cannot reach the template library" do
    template = BriefTemplate.capture!(create_brief("HQ seulement"))
    sign_in @brand.store_user

    get brief_templates_path
    assert_response :redirect

    post use_brief_template_path(template)
    assert_response :redirect
    assert_equal 1, @tenant.communications.where(title_fr: "HQ seulement").count
  end

  test "HQ can delete a template" do
    template = BriefTemplate.capture!(create_brief("A supprimer"))
    sign_in @brand.hq

    assert_difference "BriefTemplate.count", -1 do
      delete brief_template_path(template)
    end
    assert_redirected_to brief_templates_path
  end

  test "template labels exist in every locale" do
    %i[fr en es ar].each do |locale|
      %w[title lede empty use delete delete_confirm deleted draft_created saved save_failed save_as name_placeholder proof].each do |key|
        assert I18n.exists?("brief_templates.#{key}", locale), "#{locale} #{key}"
      end
    end
  end
end
