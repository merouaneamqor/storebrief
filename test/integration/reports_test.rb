require "test_helper"

class ReportsTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "report tells headquarters to start with the oldest open store" do
    tenant = create_tenant("Atlas Reports", "atlas-reports")
    north = tenant.org_units.create!(name: "North", unit_type: "region")
    south = tenant.org_units.create!(name: "South", unit_type: "region")
    anfa = tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: north)
    gueliz = tenant.org_units.create!(name: "Gueliz", unit_type: "store", parent: south)
    agdal = tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: north)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-reports.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: north, role: "hq")

    stale = tenant.communications.create!(
      author: hq, title_fr: "Window display", body_fr: "Change the window.", format: "task", status: "sent"
    )
    done = tenant.communications.create!(
      author: hq, title_fr: "Opening note", body_fr: "Read this.", format: "news", status: "sent"
    )

    stale.deliveries.create!(org_unit: anfa, status: "pending").update_column(:created_at, 5.days.ago)
    3.times do |index|
      brief = tenant.communications.create!(
        author: hq, title_fr: "Price cards #{index}", body_fr: "Print the cards.", format: "task", status: "sent"
      )
      brief.deliveries.create!(org_unit: gueliz, status: "pending")
    end
    done.deliveries.create!(org_unit: agdal, status: "completed", completed_at: Time.current)

    sign_in(hq, tenant)

    get reports_path
    assert_response :success
    assert_select ".report-insight--urgent", text: /Anfa/
    assert_match I18n.t("reports.insight_stale", count: 1, store: "Anfa", locale: :en), response.body
    assert_select "tr.is-priority", text: /Anfa/
    assert_select "tr.is-priority", text: /Gueliz/, count: 0
    assert_select "[data-controller='reports-filter']"
    assert_select "td", text: "North"
    assert_select "td", text: "South"
    assert_match I18n.t("reports.age_stale", locale: :en), response.body
  end

  test "report stays quiet when every store is up to date" do
    tenant = create_tenant("Atlas Clear", "atlas-clear")
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-clear.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")
    brief = tenant.communications.create!(
      author: hq, title_fr: "Done brief", body_fr: "Already read.", format: "news", status: "sent"
    )
    brief.deliveries.create!(org_unit: store, status: "read", completed_at: Time.current)

    sign_in(hq, tenant)

    get reports_path
    assert_response :success
    assert_select ".report-insight--ok", text: I18n.t("reports.insight_clear", locale: :en)
    assert_select ".report-age", count: 0
  end

  test "a store user cannot open reports" do
    tenant = create_tenant("Atlas Locked Reports", "atlas-locked-reports")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store")
    user = tenant.users.create!(
      name: "Store",
      email: "store@atlas-locked-reports.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    user.memberships.create!(org_unit: store, role: "store")

    sign_in(user, tenant)

    get reports_path
    assert_redirected_to app_root_path
  end
  test "date filters and chart grouping are localized and area scoped" do
    brand = build_brand("report-period-ui")
    area = create_user(brand.tenant, org_unit: brand.region, role: :area)
    other_region = brand.tenant.org_units.create!(name: "Hidden Region", unit_type: "region")
    other_store = brand.tenant.org_units.create!(name: "Hidden Store", unit_type: "store", parent: other_region)
    [ brand.store, other_store ].each do |store|
      brief = brand.tenant.communications.create!(author: brand.hq, title_fr: "Scoped brief", body_fr: "Do it", format: "task", status: "sent")
      brief.deliveries.create!(org_unit: store, status: "pending").update_column(:created_at, Time.zone.parse("2026-01-10 12:00"))
    end
    sign_in(area)
    %w[fr ar en es].each do |locale|
      area.update!(locale: locale)
      get reports_path, params: { from: "2026-01-01", to: "2026-01-31", interval: "month", group_by: "store" }
      assert_response :success
      assert_select "input[name=from][value='2026-01-01']"
      assert_select "option[value=month][selected]"
      assert_select "canvas[data-reports-charts-target=trends]"
      assert_select "td", text: brand.store.name
      assert_no_match "Hidden Store", response.body
      assert_no_match "translation missing", response.body
    end
    get reports_path, params: { from: "999999999-12-31", to: "-999999999-01-01" }
    assert_response :success
    assert_select "input[name=from][value='2096-01-01']"
    assert_select "input[name=to][value='2100-12-31']"
    get reports_path, params: { from: "2026-02-01", to: "2026-02-28" }
    assert_response :success
    assert_select ".report-insight--ok"
    get ranking_path, params: { from: "2026-01-01", to: "2026-01-31" }
    assert_response :success
    assert_no_match "Hidden Store", response.body
  end
end
