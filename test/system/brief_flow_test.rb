require "application_system_test_case"

class BriefFlowTest < ApplicationSystemTestCase
  test "hq composes and sends a task brief, the store completes it from the inbox" do
    brand = build_brand("atlas-brief-flow")

    log_in_as(brand.hq)
    visit new_communication_path
    wait_for_alpine
    find(".brief-title").fill_in with: "Alarm check"
    find(".brief-description").fill_in with: "Confirm the alarms are off before opening."
    assert_selector ".brief-topbar__title", text: "Alarm check"
    assert_field "communication[body_fr]", with: "Confirm the alarms are off before opening."

    within(".brief-topbar__actions") { click_button I18n.t("communications.send", locale: :en) }
    within ".brief-settings__panel" do
      find("label.brief-choice", text: I18n.t("common.task", locale: :en)).click
      find("label.brief-target", text: brand.store.name).click
      assert_selector ".brief-chip", text: brand.store.name
      within(".brief-settings__actions") { click_button I18n.t("communications.send", locale: :en) }
    end

    assert_text I18n.t("communications.sent", locale: :en)
    brief = brand.tenant.communications.last
    assert_equal "sent", brief.status
    assert brief.task?
    log_out

    log_in_as(brand.store_user)
    visit inbox_path(brief.deliveries.first)
    assert_text "Confirm the alarms are off before opening."
    %w[received read understood in_progress done].each do |step|
      click_button I18n.t("morocco.awareness.actions.#{step}", locale: :en)
    end

    assert_text I18n.t("morocco.awareness.saved", locale: :en)
    assert_equal "completed", brief.deliveries.first.reload.status
  end
end
