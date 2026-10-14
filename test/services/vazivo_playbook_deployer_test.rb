require "test_helper"

class VazivoPlaybookDeployerTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("deploy-range")
    Playbook.ensure_defaults!(@brand.tenant)
    @playbook = @brand.tenant.playbooks.find_by!(key: "sale")
    @campaign_on = Date.new(2026, 6, 16)
  end

  test "deploy persists starts_on campaign window and bilingual brief bodies" do
    starts_on = Date.new(2026, 6, 9)

    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: @brand.hq,
      starts_on: starts_on,
      campaign_on: @campaign_on,
      brief_fr: "Brief FR soldes",
      brief_ar: "موجز التخفيضات",
      org_unit_ids: [ @brand.store.id ]
    )

    checklist = @brand.tenant.checklists.order(:id).last
    assert_equal starts_on, checklist.starts_on
    assert_equal @campaign_on, checklist.campaign_on
    assert_equal "Brief FR soldes", checklist.description_fr
    assert_equal "موجز التخفيضات", checklist.description_ar
    assert_equal 4, checklist.checklist_items.count

    communication = @brand.tenant.communications.where(source: "playbook").order(:id).last
    assert_equal "Brief FR soldes", communication.body_fr
    assert_equal "موجز التخفيضات", communication.body_ar
    assert_equal @playbook.description_fr, @playbook.reload.description_fr
  end

  test "inverted range is rejected" do
    error = assert_raises(ArgumentError) do
      Vazivo::PlaybookDeployer.deploy!(
        playbook: @playbook,
        author: @brand.hq,
        starts_on: @campaign_on + 1,
        campaign_on: @campaign_on,
        brief_fr: "Brief",
        org_unit_ids: [ @brand.store.id ]
      )
    end

    assert_equal I18n.t("morocco.playbooks.invalid_range"), error.message
    assert_equal 0, @brand.tenant.checklists.count
  end

  test "short window clamps early step titles into the range" do
    starts_on = @campaign_on - 3

    Vazivo::PlaybookDeployer.deploy!(
      playbook: @playbook,
      author: @brand.hq,
      starts_on: starts_on,
      campaign_on: @campaign_on,
      brief_fr: "Fenêtre courte",
      org_unit_ids: [ @brand.store.id ]
    )

    titles = @brand.tenant.checklists.order(:id).last.checklist_items.order(:position).map(&:title_fr)
    # sale offsets: -7, -3, -1, 0 — J-7 clamps to J-3
    assert_equal 4, titles.size
    assert_equal "J-3 · Contrôle des prix", titles.first
    assert_equal "J-3 · Signalétique soldes", titles.second
    assert_equal "J-1 · Vitrine soldes", titles.third
    assert_equal "J · Photo d'ouverture", titles.last
  end

  test "blank brief_fr is rejected when playbook has no description" do
    @playbook.update_columns(description_fr: "", description_ar: nil)

    error = assert_raises(ArgumentError) do
      Vazivo::PlaybookDeployer.deploy!(
        playbook: @playbook,
        author: @brand.hq,
        starts_on: @campaign_on - 7,
        campaign_on: @campaign_on,
        brief_fr: "",
        org_unit_ids: [ @brand.store.id ]
      )
    end

    assert_equal I18n.t("morocco.playbooks.brief_required"), error.message
  end
end
