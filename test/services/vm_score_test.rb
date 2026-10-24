require "test_helper"

class VmScoreTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("vm-score")
    @tenant = @brand.tenant
    @north = @tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @tanger = @tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @north)
    @week = Vazivo::Schedule.now.beginning_of_week.to_date
  end

  def mission_for(stores, deadline: @week + 2.days)
    mission = @tenant.vm_missions.new(
      title_fr: "Vitrine", instructions_fr: "Photographier.", deadline_on: deadline,
      created_by: @brand.hq, status: "open"
    )
    mission.sync_targets!(stores.map(&:id))
    mission.save!
    mission
  end

  def finish(mission, store, verdict, submitted_at: mission.deadline_on.in_time_zone)
    mission.vm_mission_targets.find_by!(org_unit: store).update!(
      status: "completed", verdict: verdict, submitted_at: submitted_at, validated_at: Time.current
    )
  end

  def week_range
    @week..(@week + 6.days)
  end

  test "verdicts map to points and late proof loses a penalty" do
    mission = mission_for([ @brand.store, @tanger ])
    finish(mission, @brand.store, "improve")
    finish(mission, @tanger, "conforme", submitted_at: (mission.deadline_on + 1.day).in_time_zone)

    scores = Vazivo::VmScore.for(@tenant, week_range)
    assert_equal 60, scores[@brand.store.id].percent
    assert_equal 80, scores[@tanger.id].percent
  end

  test "a missed deadline scores zero but an open mission is not scored yet" do
    overdue = mission_for([ @brand.store ], deadline: Date.current - 1.day)
    upcoming = mission_for([ @tanger ], deadline: Date.current + 3.days)

    scores = Vazivo::VmScore.for(@tenant, (Date.current - 1.day)..(Date.current + 3.days))
    assert_equal 0, scores[@brand.store.id].percent
    assert_nil scores[@tanger.id]
    assert overdue.persisted? && upcoming.persisted?
  end

  test "ranking exposes the best merchandising store and compares areas" do
    mission = mission_for([ @brand.store, @tanger ])
    finish(mission, @brand.store, "conforme")
    finish(mission, @tanger, "improve")

    ranking = Vazivo::Ranking.for(@tenant, on: @week.in_time_zone)
    assert_equal @brand.store, ranking.awards[:merchandising].store
    assert_equal [ "Casa", "Nord" ], ranking.vm_areas.map { |area| area.unit.name }
    assert_equal [ 100, 60 ], ranking.vm_areas.map(&:percent)
  end

  test "other tenants missions never leak into the score" do
    other = build_brand("vm-score-other")
    foreign = other.tenant.vm_missions.new(
      title_fr: "X", instructions_fr: "Y", deadline_on: @week + 1.day, created_by: other.hq, status: "open"
    )
    foreign.sync_targets!([ other.store.id ])
    foreign.save!
    foreign.vm_mission_targets.first.update!(status: "completed", verdict: "conforme", submitted_at: Time.current)

    assert_empty Vazivo::VmScore.for(@tenant, week_range)
  end

  test "ranking page shows the merchandising score and regional comparison" do
    mission = mission_for([ @brand.store, @tanger ])
    finish(mission, @brand.store, "conforme")
    finish(mission, @tanger, "improve")

    sign_in(@brand.hq)
    get ranking_path
    assert_response :success
    assert_select "h2", text: I18n.t("morocco.ranking.vm.title")
    assert_select "h2", text: I18n.t("morocco.ranking.vm.regional_title")
    assert_select "td", text: "Tanger"
    assert_select "td", text: "Nord"
  end
end
