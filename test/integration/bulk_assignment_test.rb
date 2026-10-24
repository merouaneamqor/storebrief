require "test_helper"

class BulkAssignmentTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("bulk-ui", features: { briefs: true, checklists: true })
    @store_b = @brand.tenant.org_units.create!(
      name: "Anfa",
      unit_type: "store",
      parent: @brand.region,
      store_format: "flagship",
      cluster_key: "casa-center"
    )
    @brand.store.update!(store_format: "express", cluster_key: "casa-south")
    create_user(@brand.tenant, org_unit: @store_b, role: :store, email: "store-b@bulk-ui.test")
    sign_in @brand.hq
  end

  test "HQ can preview stores matching assignment filters" do
    get preview_targets_communications_path(format: :json), params: {
      org_unit_ids: [ @brand.region.id ],
      store_format: "flagship",
      cluster: "casa-center"
    }

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["count"]
    assert_equal @store_b.id, body["stores"].first["id"]
    assert_includes body["summary"], "1"
  end

  test "compose send applies role format and cluster filters" do
    post communications_path, params: {
      commit: "send",
      org_unit_ids: [ @brand.region.id ],
      assignment_role: "store",
      store_format: "express",
      cluster: "casa-south",
      communication: {
        title_fr: "Express only",
        body_fr: "Check shelves.",
        format: "task"
      }
    }

    brief = @brand.tenant.communications.order(:id).last
    assert_redirected_to communication_path(brief)
    assert_equal [ @brand.store.id ], brief.deliveries.pluck(:org_unit_id)
  end

  test "checklist send applies assignment filters" do
    template = @brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Open",
      items: [ { title_fr: "Lights", requires_photo: false } ]
    )
    checklist = Checklist.build_from_template(template, author: @brand.hq)
    checklist.save!

    post send_checklist_checklist_path(checklist), params: {
      org_unit_ids: [ @brand.region.id ],
      store_format: "flagship",
      cluster: "casa-center"
    }

    assert_redirected_to checklist_path(checklist)
    assert_equal [ @store_b.id ], checklist.reload.checklist_deliveries.pluck(:org_unit_id)
  end

  test "compose targeting UI exposes assignment filters" do
    get new_communication_path

    assert_response :success
    assert_select "[data-preview-url]"
    assert_select "select[aria-label=?]", I18n.t("communications.filter_role", locale: :en)
    assert_select "select[aria-label=?]", I18n.t("communications.filter_format", locale: :en)
    assert_select "select[aria-label=?]", I18n.t("communications.filter_cluster", locale: :en)
  end
end
