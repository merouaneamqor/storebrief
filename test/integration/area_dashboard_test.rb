require "test_helper"

class AreaDashboardTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @tenant = create_tenant("Atlas Area", "atlas-area", features: Tenant.default_features.merge("morocco_ops" => true))
    @region = @tenant.org_units.create!(name: "Maroc", unit_type: "region")
    @casa = @tenant.org_units.create!(name: "Casa Centre", unit_type: "area", parent: @region)
    @rabat = @tenant.org_units.create!(name: "Rabat Agdal", unit_type: "area", parent: @region)
    @maarif = @tenant.org_units.create!(name: "Store Maarif", unit_type: "store", parent: @casa)
    @diab = @tenant.org_units.create!(name: "Store Ain Diab", unit_type: "store", parent: @casa)
    @agdal = @tenant.org_units.create!(name: "Store Agdal", unit_type: "store", parent: @rabat)

    @hq = create_user(@tenant, org_unit: @region, role: :hq)
    @area_user = create_user(@tenant, org_unit: @casa, role: :area)
    @rabat_user = create_user(@tenant, org_unit: @rabat, role: :area, email: "rabat-area@atlas-area.test")
  end

  test "area manager sees aggregates over descendant stores only" do
    brief = send_task("Campagne Aid", [ @maarif, @diab, @agdal ])
    finish(brief, @maarif, verdict: "conforme")
    late(brief, @diab)
    late(brief, @agdal)
    redo!(brief, @agdal)

    sign_in(@area_user)
    assert_response :success
    assert_select ".area-summary"
    assert_select ".area-pulse .hq-pulse__tile", 4
    assert_match I18n.t("morocco.radar.area.compliance", locale: :en), response.body

    summary = Vazivo::Radar.for(user: @area_user, tenant: @tenant).area
    assert_equal 2, summary.stores_count
    assert_equal 2, summary.tasks_total
    assert_equal 1, summary.tasks_done
    assert_equal 50, summary.compliance_percent
    assert_equal 1, summary.tasks_open
    assert_equal 1, summary.tasks_late
    assert_equal 1, summary.audits["conforme"]
    assert_equal 0, summary.audits["non_conforme"]
    assert_equal 2, summary.campaign.total
    assert_equal [ "Store Ain Diab" ], summary.attention_stores.map(&:name)
  end

  test "area manager never sees another area" do
    brief = send_task("Campagne Aid", [ @maarif, @agdal ])
    late(brief, @agdal)
    redo!(brief, @agdal)

    sign_in(@area_user)
    assert_no_match(/Store Agdal/, response.body)
    assert_no_match(/Rabat Agdal/, response.body)

    summary = Vazivo::Radar.for(user: @area_user, tenant: @tenant).area
    assert_equal 2, summary.stores_count
    assert_equal 1, summary.campaign.total
    assert_equal 0, summary.audits["non_conforme"]
    assert_equal 0, summary.tasks_late
    assert_not_includes summary.attention_stores.map(&:name), "Store Agdal"

    delete logout_path
    sign_in(@rabat_user)
    assert_match(/Store Agdal/, response.body)
    assert_no_match(/Store Maarif/, response.body)
  end

  test "area manager never sees another tenant" do
    other = create_tenant("Other Brand", "other-brand", features: Tenant.default_features.merge("morocco_ops" => true))
    other_region = other.org_units.create!(name: "Other Region", unit_type: "region")
    other_store = other.org_units.create!(name: "Foreign Store", unit_type: "store", parent: other_region)
    other_hq = create_user(other, org_unit: other_region, role: :hq)
    foreign = other.communications.create!(
      author: other_hq, title_fr: "Foreign campaign", body_fr: "x", format: "task", status: "draft", source: "playbook"
    )
    foreign.send_to!([ other_store.id ])

    sign_in(@area_user)
    assert_no_match(/Foreign/, response.body)
    summary = Vazivo::Radar.for(user: @area_user, tenant: @tenant).area
    assert_nil summary.campaign
    assert_empty summary.attention_stores
  end

  test "area manager has no head office actions" do
    sign_in(@area_user)

    [ new_communication_path, playbooks_path, billing_path ].each do |path|
      get path
      assert_redirected_to app_root_path, "expected #{path} to be blocked for area role"
    end
    patch ramadan_path
    assert_redirected_to app_root_path
  end

  test "area dashboard copy exists in every locale without em dashes" do
    keys = I18n.t("morocco.radar.area", locale: :en).keys
    %i[fr en es ar].each do |locale|
      copy = I18n.t("morocco.radar.area", locale: locale)
      assert_equal keys.sort, copy.keys.sort, "missing keys for #{locale}"
      assert copy.values.none? { |value| value.include?("—") }, "em dash in #{locale}"
    end
  end

  test "area store table sorts by score and opens that store radar" do
    brief = send_task("Campagne Aid", [ @maarif, @diab ])
    finish(brief, @maarif, verdict: "conforme")
    late(brief, @diab)

    sign_in(@area_user)
    assert_select "table.area-store-table"
    assert_select "a[href='#{store_path(@maarif)}']", text: @maarif.name
    assert_select "a[href='#{store_path(@diab)}']", text: @diab.name
    assert_select ".store-status-badge--critical", text: I18n.t("morocco.hq.store_status.critical", locale: :en)
    assert_no_match(/Store Agdal/, response.body)
    assert_equal [ @maarif.name, @diab.name ], store_table_names

    get app_root_path(sort: "score_asc")
    assert_response :success
    assert_equal [ @diab.name, @maarif.name ], store_table_names

    get store_path(@maarif)
    assert_response :success
    assert_match @maarif.name, response.body
    assert_select "table.area-store-table", 0

    get store_path(@agdal)
    assert_response :not_found
  end

  test "head office keeps the exception board" do
    send_task("Campagne Aid", [ @maarif ])
    sign_in(@hq)
    assert_select ".hq-hero"
    assert_select ".area-summary", 0
  end

  private

  def store_table_names
    css_select("table.area-store-table tbody td a").map(&:text)
  end

  def send_task(title, stores)
    brief = @tenant.communications.create!(
      author: @hq, title_fr: title, body_fr: "Corps", format: "task", status: "draft", source: "playbook"
    )
    brief.send_to!(stores.map(&:id))
    brief
  end

  def finish(brief, store, verdict: nil)
    delivery = brief.deliveries.find_by!(org_unit: store)
    delivery.update!(status: "completed", completed_at: Time.current, awareness: "done")
    delivery.apply_verdict!(verdict, note: nil, by: @hq) if verdict
  end

  def late(brief, store)
    brief.deliveries.find_by!(org_unit: store).update!(due_at: 2.hours.ago)
  end

  def redo!(brief, store)
    brief.deliveries.find_by!(org_unit: store).apply_verdict!("non_conforme", note: nil, by: @hq)
  end
end
