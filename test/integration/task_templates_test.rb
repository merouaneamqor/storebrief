require "test_helper"

class TaskTemplatesTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("atlas-task-templates")
  end

  test "hq creates edits and deletes a task template" do
    sign_in(@brand.hq)

    get new_task_template_path
    assert_response :success

    assert_difference -> { @brand.tenant.communication_templates.count }, 1 do
      post task_templates_path, params: {
        communication_template: {
          title_fr: "Facing matin",
          title_ar: "واجهة الصباح",
          body_fr: "Corriger le facing.",
          body_ar: "",
          format: "task",
          priority: "important",
          requires_proof: "1",
          questions: {
            "0" => {
              position: "0",
              question_type: "short_text",
              title_fr: "Facing OK ?",
              title_ar: "الواجهة جيدة؟",
              required: "1"
            },
            "1" => {
              position: "1",
              question_type: "image",
              title_fr: "Photo rayon",
              required: "0"
            }
          }
        }
      }
    end

    template = @brand.tenant.communication_templates.order(:id).last
    assert_redirected_to task_templates_path
    assert_equal "Facing matin", template.title_fr
    assert_equal "task", template.format
    assert_equal "important", template.priority
    assert template.requires_proof?
    assert_equal 2, template.question_count
    assert_equal "Facing OK ?", template.question_defs.first[:title_fr]

    get edit_task_template_path(template)
    assert_response :success

    patch task_template_path(template), params: {
      communication_template: {
        title_fr: "Facing matin v2",
        title_ar: "واجهة الصباح",
        body_fr: "Corriger le facing.",
        format: "task",
        priority: "urgent",
        requires_proof: "0",
        questions: {
          "0" => {
            position: "0",
            question_type: "short_text",
            title_fr: "Facing OK ?",
            required: "1"
          }
        }
      }
    }
    assert_redirected_to task_templates_path
    assert_equal "Facing matin v2", template.reload.title_fr
    assert_equal "urgent", template.priority
    assert_not template.requires_proof?
    assert_equal 1, template.question_count

    assert_difference -> { @brand.tenant.communication_templates.count }, -1 do
      delete task_template_path(template)
    end
    assert_redirected_to task_templates_path
  end

  test "use builds a draft communication from the template" do
    template = @brand.tenant.communication_templates.create!(
      title_fr: "Promo vitrine",
      body_fr: "Mettre la PLV.",
      format: "task",
      priority: "routine",
      requires_proof: true,
      questions: [
        {
          "position" => 0,
          "question_type" => "short_text",
          "title_fr" => "PLV placée ?",
          "required" => true,
          "options" => []
        }
      ]
    )

    sign_in(@brand.hq)
    assert_difference -> { @brand.tenant.communications.count }, 1 do
      post use_task_template_path(template)
    end

    brief = @brand.tenant.communications.order(:id).last
    assert_equal "draft", brief.status
    assert_equal template.id, brief.communication_template_id
    assert_equal "Promo vitrine", brief.title_fr
    assert_equal "Mettre la PLV.", brief.body_fr
    assert brief.requires_proof?
    assert_equal 1, brief.communication_questions.count
    assert_equal "PLV placée ?", brief.communication_questions.first.title_fr
    assert_redirected_to edit_communication_path(brief)
  end

  test "hq can save a sent brief as a template" do
    brief = @brand.tenant.communications.create!(
      author: @brand.hq,
      title_fr: "Ouverture caisse",
      body_fr: "Vérifier les caisses.",
      format: "task",
      status: "draft",
      priority: "important",
      requires_proof: false
    )
    brief.communication_questions.create!(
      position: 0,
      question_type: "short_text",
      title_fr: "Caisses OK ?",
      required: true
    )
    brief.update_columns(status: "sent")

    sign_in(@brand.hq)
    assert_difference -> { @brand.tenant.communication_templates.count }, 1 do
      post save_as_template_communication_path(brief)
    end

    template = @brand.tenant.communication_templates.order(:id).last
    assert_redirected_to task_templates_path
    assert_equal "Ouverture caisse", template.title_fr
    assert_equal "Vérifier les caisses.", template.body_fr
    assert_equal "important", template.priority
    assert_equal 1, template.question_count
    assert_equal "Caisses OK ?", template.question_defs.first[:title_fr]
  end

  test "task templates are tenant scoped" do
    other = build_brand("contoso-task-templates")
    foreign = other.tenant.communication_templates.create!(
      title_fr: "Autre tenant",
      body_fr: "Secret",
      format: "task",
      questions: []
    )

    sign_in(@brand.hq)
    get edit_task_template_path(foreign)
    assert_response :not_found

    patch task_template_path(foreign), params: {
      communication_template: { title_fr: "Hack", body_fr: "Hack", format: "task", questions: [] }
    }
    assert_response :not_found

    delete task_template_path(foreign)
    assert_response :not_found
    assert foreign.reload.persisted?

    post use_task_template_path(foreign)
    assert_response :not_found
  end

  test "store users cannot manage task templates" do
    sign_in(@brand.store_user)
    get new_task_template_path
    assert_redirected_to app_root_path

    get task_templates_path
    assert_redirected_to app_root_path
  end

  test "draft from template can be sent to targets" do
    template = @brand.tenant.communication_templates.create!(
      title_fr: "Déploiement",
      body_fr: "Appliquer la consigne.",
      format: "task",
      questions: []
    )

    sign_in(@brand.hq)
    post use_task_template_path(template)
    brief = @brand.tenant.communications.order(:id).last

    assert_difference -> { brief.deliveries.count }, 1 do
      post send_brief_communication_path(brief), params: { org_unit_ids: [ @brand.store.id ] }
    end
    assert_redirected_to communication_path(brief)
    assert_equal "sent", brief.reload.status
  end
end
