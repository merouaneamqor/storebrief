require "test_helper"
require "csv"
require "zip"

class SpreadsheetExportsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("exports-ma")
    @brand.store.update!(name: "متجر الرباط")
    @other_region = @brand.tenant.org_units.create!(name: "Other region", unit_type: "region")
    @other_store = @brand.tenant.org_units.create!(name: "Invisible Store", unit_type: "store", parent: @other_region)
    @area = create_user(@brand.tenant, org_unit: @brand.region, role: :area)
    @brief = @brand.tenant.communications.create!(author: @brand.hq, title_fr: "=HYPERLINK(\"bad\")", body_fr: "Read", format: "news", status: "sent")
    @delivery = @brief.deliveries.create!(org_unit: @brand.store, status: "completed", completed_at: Time.current)
    @brief.deliveries.create!(org_unit: @other_store, status: "pending")
    @params = { from: Date.current.iso8601, to: Date.current.iso8601 }
  end

  test "reports export filtered rows in each locale and format with tenant and area scopes and audit metadata" do
    sign_in(@area)
    %w[fr ar en es].each do |locale|
      %w[csv xlsx].each do |output|
        assert_difference "ExportLog.count", 1 do
          get reports_path(format: output), params: @params.merge(locale: locale, query: "متجر", state: "clear")
        end
        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_includes response.headers["Content-Disposition"], ".#{output}"
        assert_equal I18n.t("spreadsheet_exports.columns.store", locale: locale), exported_rows(output).first.first
        assert_equal "متجر الرباط", exported_rows(output).last.first
        assert_equal 2, exported_rows(output).size
        refute_includes response.body, "Invisible Store" if output == "csv"
        log = ExportLog.last
        assert_equal @brand.tenant.id, log.tenant_id
        assert_equal @area.id, log.actor_id
        assert_equal 1, log.row_count
        assert_equal locale, log.filters["locale"]
        assert_equal @params[:from], log.filters["from"]
        assert_equal "clear", log.filters["state"]
      end
    end
    get reports_path(format: :csv), params: @params.merge(state: "behind")
    assert_equal 1, exported_rows("csv").size
    assert_equal 0, ExportLog.last.row_count
    get reports_path(format: :csv), params: { from: "2020-01-01", to: "2020-01-02", state: "behind" }
    assert_equal 1, exported_rows("csv").size
  end

  test "brief and checklist delivery monitoring exports preserve roles, scope and formula safety" do
    sign_in(@area)
    %w[csv xlsx].each do |output|
      get communication_path(@brief, format: output)
      assert_response :success
      rows = exported_rows(output)
      assert_equal 2, rows.size
      assert_equal "متجر الرباط", rows.last.first
      assert_equal output == "csv" ? "'#{@brief.title}" : @brief.title, rows.last[1]
      assert_equal "brief-deliveries", ExportLog.last.source
    end
    sign_in(@brand.store_user)
    assert_no_difference "ExportLog.count" do
      get communication_path(@brief, format: :csv)
      assert_response :redirect
    end
    sign_in(@brand.hq)
    checklist = create_campaign
    %w[csv xlsx].each do |output|
      get checklist_path(checklist, format: output)
      assert_response :success
      assert_equal "متجر الرباط", exported_rows(output).last.first
      assert_equal "checklist-deliveries", ExportLog.last.source
    end
  end

  test "campaign closing downloads and printable HTML are logged and restricted to HQ and tenant" do
    sign_in(@brand.hq)
    checklist = create_campaign
    %w[csv xlsx].each do |output|
      assert_difference "ExportLog.count", 1 do
        get closing_report_playbooks_path(checklist, format: output)
      end
      assert_response :success
      assert_equal "متجر الرباط", exported_rows(output).last.first
      assert_equal checklist.id, ExportLog.last.filters["checklist_id"]
    end
    assert_difference "ExportLog.count", 1 do
      get closing_report_playbooks_path(checklist, export: 1)
    end
    assert_response :success
    assert_equal "html", ExportLog.last.output_format
    sign_in(@area)
    assert_no_difference "ExportLog.count" do
      get closing_report_playbooks_path(checklist, format: :xlsx)
      assert_response :redirect
    end
    foreign = build_brand("foreign-export")
    sign_in(foreign.hq)
    assert_no_difference "ExportLog.count" do
      get closing_report_playbooks_path(checklist, format: :csv)
      assert_response :not_found
    end
  end

  test "ranking exports respect dates and non HQ stores and disabled features do not export" do
    sign_in(@brand.store_user)
    %w[csv xlsx].each do |output|
      get ranking_path(format: output), params: @params
      assert_response :success
      assert_equal 2, exported_rows(output).size
      assert_equal "متجر الرباط", exported_rows(output).last.first
      assert_equal "ranking", ExportLog.last.source
    end
    get ranking_path(format: :csv), params: { from: "2020-01-01", to: "2020-01-02" }
    assert_equal 1, exported_rows("csv").size
    @brand.tenant.update!(features: @brand.tenant.features.merge("morocco_ops" => false))
    assert_no_difference "ExportLog.count" do
      get ranking_path(format: :xlsx)
      assert_response :redirect
    end
  end

  test "download links preserve report date and grouping filters" do
    sign_in(@brand.hq)
    get reports_path, params: @params.merge(interval: "month", group_by: "store")
    assert_response :success
    assert_select "a[data-reports-filter-target=download]", count: 2
    assert_select "a[href*='from=#{Date.current.iso8601}'][href*='interval=month'][href*='group_by=store']", count: 2
  end

  private

  def create_campaign
    Playbook.ensure_defaults!(@brand.tenant)
    playbook = @brand.tenant.playbooks.first
    Vazivo::PlaybookDeployer.deploy!(playbook: playbook, author: @brand.hq, starts_on: Date.current - 5,
      campaign_on: Date.current - 1, brief_fr: playbook.description_fr, org_unit_ids: [ @brand.store.id ])
    @brand.tenant.checklists.order(:id).last
  end

  def exported_rows(format)
    if format == "csv"
      CSV.parse(response.body.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF"))
    else
      rows = nil
      Zip::File.open_buffer(response.body) do |zip|
        document = Nokogiri::XML(zip.read("xl/worksheets/sheet1.xml"))
        document.remove_namespaces!
        rows = document.xpath("//row").map { |row| row.xpath("c").map { |cell| cell.at_xpath("is/t|v")&.text } }
      end
      rows
    end
  end
end
