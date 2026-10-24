require "test_helper"

class AnnouncementsTest < ActionDispatch::IntegrationTest
  setup { host! "localhost" }

  test "HQ can create an announcement targeted at a region with PDF and photo attachments" do
    tenant = create_tenant("Atlas Announce", "atlas-announce")
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    other_region = tenant.org_units.create!(name: "Rabat", unit_type: "region")
    other_store = tenant.org_units.create!(name: "Agdal", unit_type: "store", parent: other_region)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-announce.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")

    post login_path, params: { tenant_slug: tenant.slug, email: hq.email, password: "password" }
    follow_redirect!

    get new_communication_path
    assert_response :success
    assert_select "input[type=radio][value=announcement]"
    assert_select "input[type=file][name='communication[attachments][]']"

    assert_difference -> { tenant.communications.count }, 1 do
      assert_difference -> { Delivery.count }, 1 do
        post communications_path, params: {
          communication: {
            title_fr: "Ramadan hours",
            body_fr: "Updated opening hours for all Casa stores.",
            format: "announcement",
            attachments: [
              fixture_file_upload("notice.pdf", "application/pdf"),
              fixture_file_upload("window.jpg", "image/jpeg")
            ]
          },
          org_unit_ids: [ region.id ],
          commit: "send"
        }
      end
    end

    announcement = tenant.communications.order(:id).last
    assert_equal "announcement", announcement.format
    assert_equal "sent", announcement.status
    assert announcement.announcement?
    assert announcement.attachments?
    assert_equal 2, announcement.attachments.count
    assert_equal [ store.id ], announcement.deliveries.pluck(:org_unit_id)
    assert_not_includes announcement.deliveries.pluck(:org_unit_id), other_store.id
    assert_redirected_to communication_path(announcement)

    follow_redirect!
    assert_response :success
    assert_select ".badge", text: I18n.t("common.announcement", locale: :en)
    assert_select ".brief-attachments"
    assert_select ".brief-attachments a", text: /notice\.pdf/
    assert_select ".brief-attachments a", text: /window\.jpg/
  end

  test "HQ can target individual stores for an announcement draft" do
    tenant = create_tenant("Atlas Announce Store", "atlas-announce-store")
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    store_a = tenant.org_units.create!(name: "Maarif", unit_type: "store", parent: region)
    store_b = tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: region)
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-announce-store.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")

    post login_path, params: { tenant_slug: tenant.slug, email: hq.email, password: "password" }
    follow_redirect!

    assert_difference -> { tenant.communications.count }, 1 do
      post communications_path, params: {
        communication: {
          title_fr: "Window check",
          body_fr: "Please review the new planogram.",
          format: "announcement",
          attachments: [ fixture_file_upload("window.jpg", "image/jpeg") ]
        },
        org_unit_ids: [ store_a.id ],
        commit: "draft"
      }
    end

    announcement = tenant.communications.order(:id).last
    assert_equal "draft", announcement.status
    assert_equal "announcement", announcement.format
    assert_equal 1, announcement.attachments.count
    assert_redirected_to edit_communication_path(announcement)

    assert_difference -> { Delivery.count }, 1 do
      patch communication_path(announcement), params: {
        communication: {
          title_fr: "Window check",
          body_fr: "Please review the new planogram.",
          format: "announcement"
        },
        org_unit_ids: [ store_a.id ],
        commit: "send"
      }
    end

    announcement.reload
    assert_equal "sent", announcement.status
    assert_equal [ store_a.id ], announcement.deliveries.pluck(:org_unit_id)
    assert_not_includes announcement.deliveries.pluck(:org_unit_id), store_b.id
  end

  test "rejects non PDF or photo attachments on announcements" do
    tenant = create_tenant("Atlas Announce Bad", "atlas-announce-bad")
    region = tenant.org_units.create!(name: "Casa", unit_type: "region")
    hq = tenant.users.create!(
      name: "HQ",
      email: "hq@atlas-announce-bad.test",
      password: "password",
      password_confirmation: "password",
      locale: "en"
    )
    hq.memberships.create!(org_unit: region, role: "hq")

    post login_path, params: { tenant_slug: tenant.slug, email: hq.email, password: "password" }
    follow_redirect!

    assert_no_difference -> { tenant.communications.count } do
      post communications_path, params: {
        communication: {
          title_fr: "Bad file",
          body_fr: "Should fail.",
          format: "announcement",
          attachments: [ fixture_file_upload("notes.txt", "text/plain") ]
        },
        commit: "draft"
      }
    end

    assert_response :unprocessable_entity
  end
end
