require "test_helper"

class ReportTrendsTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("report-trends")
    @area = @brand.tenant.org_units.create!(name: "Area", unit_type: "area", parent: @brand.region)
    @brand.store.update!(parent: @area)
    @range = Reports::DateRange.new(from: "2026-01-05", to: "2026-02-01")
  end

  test "inclusive Morocco dates normalize reversed and invalid input" do
    reversed = Reports::DateRange.new(from: "2026-02-01", to: "2026-01-05")
    assert_equal @range.dates, reversed.dates
    assert_equal Date.new(2026, 1, 5), @range.times.begin.to_date
    assert_equal Date.new(2026, 2, 2), @range.times.end.to_date
    assert @range.times.exclude_end?
    invalid = Reports::DateRange.new(from: "bad", to: "2026-13-99", default_from: @range.from, default_to: @range.to)
    assert_equal @range.dates, invalid.dates
  end

  test "extreme and reversed dates produce a bounded chart and safe timezone range" do
    extreme = Reports::DateRange.new(from: "-999999999-01-01", to: "999999999-12-31")
    reversed = Reports::DateRange.new(from: "999999999-12-31", to: "-999999999-01-01")
    assert_equal extreme.dates, reversed.dates
    assert_equal Date.new(2100, 12, 31), extreme.to
    assert_equal Date.new(2096, 1, 1), extreme.from
    assert_equal extreme.from, extreme.times.begin.to_date
    assert_equal extreme.to + 1.day, extreme.times.end.to_date
    weekly = Reports::ComplianceTrends.new(@brand.tenant, date_range: extreme).chart
    monthly = Reports::ComplianceTrends.new(@brand.tenant, date_range: extreme, interval: "month").chart
    assert_operator weekly[:labels].size, :<=, 263
    assert_equal 60, monthly[:labels].size
    assert_equal [ Date.new(2000, 1, 1) ], Reports::DateRange.new(from: "0001-01-01", to: "0002-01-01").dates.to_a
    assert_equal Date.new(2022, 1, 1), Reports::DateRange.new(from: "2000-01-01", to: "2026-12-31").from
  end

  test "weekly and monthly compliance groups count work and preserve gaps across tenant and store boundaries" do
    add_brief(@brand, @brand.store, "2026-01-05 10:00", "completed")
    add_brief(@brand, @brand.store, "2026-01-06 10:00", "pending")
    add_brief(@brand, @brand.store, "2026-02-01 23:59", "read")
    add_brief(@brand, @brand.store, "2026-02-02 00:00", "pending")
    foreign = build_brand("foreign-trends")
    add_brief(foreign, foreign.store, "2026-01-05 10:00", "pending")
    other = @brand.tenant.org_units.create!(name: "Other", unit_type: "store", parent: @area)
    add_brief(@brand, other, "2026-01-05 10:00", "pending")

    %w[region area store].each do |group|
      chart = Reports::ComplianceTrends.new(@brand.tenant, date_range: @range, store_ids: [ @brand.store.id ], group_by: group).chart
      assert_equal [ 50, nil, nil, 100 ], chart[:series].sole[:values]
      assert_equal({ "region" => @brand.region.name, "area" => @area.name, "store" => @brand.store.name }[group], chart[:series].sole[:name])
    end
    monthly = Reports::ComplianceTrends.new(@brand.tenant, date_range: @range, store_ids: [ @brand.store.id ], interval: "month").chart
    assert_equal [ 50, 100 ], monthly[:series].sole[:values]
    report = Reports::Snapshot.new(@brand.tenant, date_range: @range, store_ids: [ @brand.store.id ])
    assert_equal 67, report.summary[:brief_percent]
    assert_equal 1, report.summary[:open_briefs]
    assert_equal [ @brand.store ], report.store_rows.map { |row| row[:store] }
  end

  test "rankings compare the immediately preceding equal length period" do
    add_brief(@brand, @brand.store, "2026-01-05 10:00", "completed")
    add_brief(@brand, @brand.store, "2026-01-06 10:00", "pending")
    add_brief(@brand, @brand.store, "2025-12-09 10:00", "pending")
    result = Vazivo::Ranking.for(@brand.tenant, date_range: @range, store_ids: [ @brand.store.id ])
    assert_equal 50, result.rows.sole.percent
    assert_equal 0, result.rows.sole.previous_percent
    assert_equal 50, result.rows.sole.delta
    assert_empty Vazivo::Ranking.for(@brand.tenant, date_range: @range, store_ids: []).rows
  end

  test "ranking comparison can precede the earliest selectable date" do
    add_brief(@brand, @brand.store, "2000-01-01 12:00", "completed")
    add_brief(@brand, @brand.store, "1999-12-31 12:00", "pending")
    range = Reports::DateRange.new(from: "2000-01-01", to: "2000-01-01")
    row = Vazivo::Ranking.for(@brand.tenant, date_range: range).rows.sole
    assert_equal 100, row.percent
    assert_equal 0, row.previous_percent
  end

  test "campaign dashboard and regional rollup share an overlapping campaign range" do
    Playbook.ensure_defaults!(@brand.tenant)
    playbook = @brand.tenant.playbooks.first
    [ Date.new(2026, 1, 15), Date.new(2026, 3, 15) ].each do |day|
      Vazivo::PlaybookDeployer.deploy!(playbook: playbook, author: @brand.hq, starts_on: day - 5,
        campaign_on: day, brief_fr: playbook.description_fr, org_unit_ids: [ @brand.store.id ])
    end
    snapshot = Vazivo::CampaignDashboard.for(@brand.tenant, date_range: @range)
    regional = Vazivo::RegionalCampaigns.for(@brand.tenant, date_range: @range)
    assert_equal 1, snapshot.campaigns.size
    assert_equal Date.new(2026, 1, 15), snapshot.campaigns.sole.campaign_on
    assert_equal snapshot.total, regional.total
    snapshot.campaigns.sole.checklist.checklist_deliveries.update_all(status: "completed", completed_at: Time.current)
    assert_equal 100, Vazivo::CampaignDashboard.for(@brand.tenant, date_range: @range).percent
    assert_equal 100, Vazivo::RegionalCampaigns.for(@brand.tenant, date_range: @range).percent
  end

  private

  def add_brief(brand, store, time, status)
    brief = brand.tenant.communications.create!(author: brand.hq, title_fr: "Brief", body_fr: "Instructions", format: "news", status: "sent")
    delivery = brief.deliveries.create!(org_unit: store, status: status)
    delivery.update_columns(created_at: Time.find_zone!(Vazivo::Schedule::ZONE).parse(time))
  end
end
