require "application_system_test_case"

class ChecklistFlowTest < ApplicationSystemTestCase
  test "hq sends a checklist from a template, the store ticks items and uploads a photo" do
    brand = build_brand("atlas-checklist-flow")
    brand.tenant.checklist_templates.create!(
      category: "opening",
      title_fr: "Ouverture magasin",
      items: [
        { title_fr: "Alarmes désactivées", requires_photo: false },
        { title_fr: "Photo de la vitrine", requires_photo: true }
      ]
    )

    log_in_as(brand.hq)
    visit templates_path
    click_button I18n.t("templates.use", locale: :en)
    assert_text I18n.t("checklists.draft_saved", locale: :en)
    wait_for_alpine

    find(".target-list label", text: brand.store.name).click
    click_button I18n.t("communications.send", locale: :en)
    assert_text I18n.t("checklists.sent", locale: :en)
    delivery = brand.tenant.checklists.last.checklist_deliveries.first
    log_out

    log_in_as(brand.store_user)
    visit checklists_delivery_path(delivery)
    assert_text "Ouverture magasin"
    # Wait for the delivery show page — Turbo can return from click_link first,
    # and wait_for_alpine alone also passes on the inbox (layout Alpine).
    assert_selector "h1", text: "Ouverture magasin"
    assert_selector ".checklist-item", text: "Alarmes désactivées"
    wait_for_alpine

    within(".checklist-item", text: "Alarmes désactivées") do
      fill_in "notes", with: "Alarmes OK"
      click_button I18n.t("checklists.mark_done", locale: :en)
    end
    assert_selector ".checklist-item.is-done", text: "Alarmes OK"
    assert delivery.reload.pending?
    wait_for_alpine

    within(".checklist-item", text: "Photo de la vitrine") do
      attach_file "photo", file_fixture("window.jpg").to_s
      assert_selector "img.thumb" # compressed client-side preview
      click_button I18n.t("checklists.mark_done", locale: :en)
    end

    assert_no_button I18n.t("checklists.complete", locale: :en)
    assert delivery.reload.completed?
    assert delivery.checklist_item_responses.joins(:photo_attachment).exists?
  end
end
