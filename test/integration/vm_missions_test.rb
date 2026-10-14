require "test_helper"

class VmMissionsTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("vm-missions")
    @area = @brand.tenant.org_units.create!(name: "Nord", unit_type: "area", parent: @brand.region)
    @north_store = @brand.tenant.org_units.create!(name: "Tanger", unit_type: "store", parent: @area)
  end

  def create_mission(store_ids: nil, **attrs)
    mission = @brand.tenant.vm_missions.new(
      {
        title_fr: "Vitrine Aïd",
        title_ar: "واجهة العيد",
        instructions_fr: "Installer la PLV et photographier la vitrine.",
        instructions_ar: "ركبوا مواد العرض وصوروا الواجهة.",
        deadline_on: Date.current + 5.days,
        created_by: @brand.hq,
        status: "open"
      }.merge(attrs)
    )
    mission.sync_targets!(store_ids || [ @brand.store.id ])
    mission.save!
    mission
  end



  test "hq creates a bilingual mission with deadline and target stores" do
    sign_in(@brand.hq)

    get new_vm_mission_path
    assert_response :success
    assert_select "a.app-nav-link[href='#{vm_missions_path}']"

    assert_difference -> { @brand.tenant.vm_missions.count }, 1 do
      post vm_missions_path, params: {
        vm_mission: {
          title_fr: "Soldes vitrine",
          title_ar: "واجهة التخفيضات",
          instructions_fr: "Mettre les prix et la PLV soldes.",
          instructions_ar: "ضعوا الأسعار ومواد التخفيضات.",
          deadline_on: "2026-11-15",
          status: "open"
        },
        org_unit_ids: [ @brand.store.id, @north_store.id ]
      }
    end

    mission = @brand.tenant.vm_missions.last
    assert_redirected_to vm_mission_path(mission)
    assert_equal "Soldes vitrine", mission.title_fr
    assert_equal "واجهة التخفيضات", mission.title_ar
    assert_equal "Mettre les prix et la PLV soldes.", mission.instructions_fr
    assert_equal Date.new(2026, 11, 15), mission.deadline_on
    assert_equal @brand.hq, mission.created_by
    assert_equal [ @brand.store.id, @north_store.id ].sort, mission.org_units.pluck(:id).sort

    follow_redirect!
    assert_match "Soldes vitrine", response.body
    assert_match @brand.store.name, response.body
    assert_match @north_store.name, response.body
  end

  test "create without stores re-renders the form" do
    sign_in(@brand.hq)

    assert_no_difference -> { VmMission.count } do
      post vm_missions_path, params: {
        vm_mission: {
          title_fr: "Sans magasin",
          instructions_fr: "Instructions",
          deadline_on: "2026-11-15",
          status: "open"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "hq updates and deletes a mission" do
    mission = create_mission
    sign_in(@brand.hq)

    get edit_vm_mission_path(mission)
    assert_response :success

    patch vm_mission_path(mission), params: {
      vm_mission: {
        title_fr: "Vitrine mise à jour",
        instructions_fr: mission.instructions_fr,
        deadline_on: mission.deadline_on.iso8601,
        status: "closed"
      },
      org_unit_ids: [ @north_store.id ]
    }
    assert_redirected_to vm_mission_path(mission)
    mission.reload
    assert_equal "Vitrine mise à jour", mission.title_fr
    assert_equal "closed", mission.status
    assert_equal [ @north_store.id ], mission.org_units.pluck(:id)

    assert_difference -> { @brand.tenant.vm_missions.count }, -1 do
      delete vm_mission_path(mission)
    end
    assert_redirected_to vm_missions_path
  end

  test "status filter narrows the list" do
    open_mission = create_mission(title_fr: "Ouverte")
    closed = create_mission(title_fr: "Cloturee", status: "closed")
    closed.sync_targets!([ @north_store.id ])
    sign_in(@brand.hq)

    get vm_missions_path(status: "closed")
    assert_match closed.title_fr, response.body
    assert_no_match(/#{Regexp.escape(open_mission.title_fr)}/, response.body.split("<main").last)
  end

  test "store users cannot manage missions" do
    sign_in(@brand.store_user)

    get vm_missions_path
    assert_redirected_to app_root_path
    assert_no_difference -> { VmMission.count } do
      post vm_missions_path, params: {
        vm_mission: {
          title_fr: "Leak",
          instructions_fr: "No",
          deadline_on: "2026-11-15",
          status: "open"
        },
        org_unit_ids: [ @brand.store.id ]
      }
    end
  end

  test "morocco_ops flag gates the mission pages" do
    brand = build_brand("vm-off", features: { morocco_ops: false })
    sign_in(brand.hq)

    get vm_missions_path
    assert_redirected_to app_root_path
  end

  test "missions are scoped to the tenant" do
    other = build_brand("vm-other")
    foreign = other.tenant.vm_missions.new(
      title_fr: "Foreign",
      instructions_fr: "Other tenant",
      deadline_on: Date.current + 2.days,
      created_by: other.hq,
      org_units: [ other.store ]
    )
    foreign.save!
    sign_in(@brand.hq)



    get edit_vm_mission_path(foreign)
    assert_response :not_found
    patch vm_mission_path(foreign), params: {
      vm_mission: { title_fr: "Hijack", instructions_fr: "x", deadline_on: foreign.deadline_on.iso8601, status: "open" },
      org_unit_ids: [ @brand.store.id ]
    }
    assert_response :not_found
    assert_equal "Foreign", foreign.reload.title_fr
  end

  test "hq cannot target a store from another tenant" do
    other = build_brand("vm-foreign-store")
    sign_in(@brand.hq)

    assert_no_difference -> { VmMission.count } do
      post vm_missions_path, params: {
        vm_mission: {
          title_fr: "Cross tenant",
          instructions_fr: "Should fail",
          deadline_on: "2026-11-15",
          status: "open"
        },
        org_unit_ids: [ other.store.id ]
      }
    end
    assert_response :unprocessable_entity
  end

  test "arabic locale surfaces bilingual title and instructions" do
    mission = create_mission
    @brand.hq.update!(locale: "ar")
    sign_in(@brand.hq)

    get vm_mission_path(mission)
    assert_response :success
    assert_match mission.title_ar, response.body
    assert_match mission.instructions_ar, response.body
  end
end
