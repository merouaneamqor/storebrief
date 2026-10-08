require "test_helper"

class BriefQuestionsTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "headquarters can draft a brief with questions and send it" do
    tenant, region, store, hq = setup_brand("atlas-questions")
    sign_in(hq, tenant)

    assert_difference -> { tenant.communications.count }, 1 do
      assert_difference -> { CommunicationQuestion.count }, 2 do
        post communications_path, params: {
          communication: {
            title_fr: "Opening form",
            body_fr: "",
            format: "task",
            communication_questions_attributes: {
              "0" => {
                position: 0,
                question_type: "short_text",
                title_fr: "Who opened?",
                required: "1",
                options: "[]"
              },
              "1" => {
                position: 1,
                question_type: "single_choice",
                title_fr: "Lights on?",
                required: "1",
                options: [ { label_fr: "Yes", label_ar: "" }, { label_fr: "No", label_ar: "" } ].to_json
              }
            }
          },
          org_unit_ids: [ store.id ],
          commit: "send"
        }
      end
    end

    brief = tenant.communications.order(:id).last
    assert_redirected_to communication_path(brief)
    assert_equal "sent", brief.status
    assert_equal 2, brief.communication_questions.count
    assert_equal [ store.id ], brief.deliveries.pluck(:org_unit_id)
  end

  test "a store cannot complete a task until required answers are present" do
    tenant, region, store, hq = setup_brand("atlas-answers")
    store_user = tenant.users.create!(
      name: "Store",
      email: "store@atlas-answers.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    store_user.memberships.create!(org_unit: store, role: "store")

    brief = tenant.communications.create!(
      author: hq,
      title_fr: "Alarms",
      body_fr: "Check alarms.",
      format: "task",
      status: "draft"
    )
    question = brief.communication_questions.create!(
      position: 0,
      question_type: "short_text",
      title_fr: "Who checked?",
      required: true
    )
    brief.send_to!([ store.id ])
    delivery = brief.deliveries.first

    sign_in(store_user, tenant)

    post complete_inbox_path(delivery), params: { answers: {} }
    assert_redirected_to inbox_path(delivery)
    follow_redirect!
    assert_match I18n.t("inbox.answers_required", locale: :en), response.body
    assert delivery.reload.pending?

    post complete_inbox_path(delivery), params: {
      answers: { question.id.to_s => { text: "Sara" } }
    }
    assert_redirected_to inbox_path(delivery)
    assert_equal "completed", delivery.reload.status
    assert_equal "Sara", delivery.delivery_answers.first.text_value
  end

  test "sent briefs reject question edits" do
    tenant, _region, store, hq = setup_brand("atlas-frozen")
    brief = tenant.communications.create!(
      author: hq,
      title_fr: "Frozen",
      body_fr: "No edits.",
      format: "news",
      status: "draft"
    )
    question = brief.communication_questions.create!(
      position: 0,
      question_type: "short_text",
      title_fr: "Locked",
      required: false
    )
    brief.send_to!([ store.id ])

    sign_in(hq, tenant)
    get edit_communication_path(brief)
    assert_redirected_to communication_path(brief)

    question.title_fr = "Changed"
    assert_not question.valid?
  end

  test "a store can complete an image question with a photo" do
    tenant, region, store, hq = setup_brand("atlas-photo")
    store_user = tenant.users.create!(
      name: "Store",
      email: "store@atlas-photo.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    store_user.memberships.create!(org_unit: store, role: "store")

    brief = tenant.communications.create!(
      author: hq,
      title_fr: "Window photo",
      body_fr: "Send the window.",
      format: "task",
      status: "draft"
    )
    question = brief.communication_questions.create!(
      position: 0,
      question_type: "image",
      title_fr: "Window photo",
      required: true
    )
    brief.send_to!([ store.id ])
    delivery = brief.deliveries.first

    sign_in(store_user, tenant)

    photo = fixture_file_upload("window.jpg", "image/jpeg")
    post complete_inbox_path(delivery), params: {
      answers: { question.id.to_s => { image: photo } }
    }
    assert_redirected_to inbox_path(delivery)
    assert_equal "completed", delivery.reload.status
    answer = delivery.delivery_answers.first
    assert answer.image.attached?
  end

  private

  def setup_brand(slug)
    tenant = Tenant.create!(
      name: slug.titleize,
      slug: slug,
      brand_name: slug.split("-").first.titleize,
      **Tenant.default_palette
    )
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@#{slug}.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")
    [ tenant, region, store, hq ]
  end
end
