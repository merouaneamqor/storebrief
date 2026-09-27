require "test_helper"

class BriefComposeTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "write a brief page uses the Google Forms style cards and can save a draft" do
    tenant = create_tenant("Atlas Compose", "atlas-compose")
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-compose.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")

    post login_path, params: { tenant_slug: tenant.slug, email: hq.email, password: "password" }
    follow_redirect!

    get new_communication_path
    assert_response :success
    assert_select ".brief-form"
    assert_select ".brief-card--title"
    assert_select "[data-controller]", count: 0
    assert_select "button", text: I18n.t("communications.preview", locale: :en)
    assert_select "button", text: I18n.t("communications.save_draft", locale: :en)
    assert_select "button", text: I18n.t("communications.send", locale: :en)
    assert_select ".brief-count"
    assert_select "input.brief-search"

    assert_difference -> { tenant.communications.count }, 1 do
      post communications_path, params: {
        communication: {
          title_fr: "Morning window",
          title_ar: "",
          body_fr: "Change the promo.",
          body_ar: "",
          format: "task"
        },
        commit: "draft"
      }
    end

    brief = tenant.communications.order(:id).last
    assert_equal "draft", brief.status
    assert_redirected_to communication_path(brief)
    follow_redirect!
    assert_select ".brief-form"
    assert_select "h2", text: I18n.t("communications.send_draft", locale: :en)
    assert_select "input.brief-search"
  end

  test "sending a brief from the form still delivers to the selected store" do
    tenant = create_tenant("Atlas Send", "atlas-send")
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-send.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")

    post login_path, params: { tenant_slug: tenant.slug, email: hq.email, password: "password" }
    follow_redirect!

    assert_difference -> { Delivery.count }, 1 do
      post communications_path, params: {
        communication: {
          title_fr: "Alarms check",
          body_fr: "Confirm alarms are off.",
          format: "task"
        },
        org_unit_ids: [ store.id ],
        commit: "send"
      }
    end

    brief = tenant.communications.order(:id).last
    assert_equal "sent", brief.status
    assert_redirected_to communication_path(brief)
    assert_equal [ store.id ], brief.deliveries.pluck(:org_unit_id)
  end

  private

  def create_tenant(name, slug)
    Tenant.create!(
      name: name,
      slug: slug,
      brand_name: name.split.first,
      **Tenant.default_palette
    )
  end
end
