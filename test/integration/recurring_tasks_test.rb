require "test_helper"

class RecurringTasksTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("recurring-ui")
    sign_in @brand.hq
  end

  test "HQ sets a weekly rule when sending a task" do
    assert_difference -> { @brand.tenant.communications.count }, 1 do
      post communications_path, params: {
        communication: {
          title_fr: "Facing rayon", body_fr: "Contrôler le facing.", format: "task",
          recurrence_attributes: { frequency: "weekly", weekdays: [ "1", "4" ], ends_on: "" }
        },
        org_unit_ids: [ @brand.store.id ],
        commit: "send"
      }
    end

    brief = @brand.tenant.communications.order(:id).last
    assert_equal({ "frequency" => "weekly", "weekdays" => [ 1, 4 ] }, brief.recurrence_rule)
    assert brief.recurrence_active?

    get communication_path(brief)
    assert_response :success
    assert_select ".brief-recurrence-card", text: /Every week on Mon, Thu/
    assert_select ".brief-recurrence-card button", text: I18n.t("communications.recurrence.stop", locale: :en)
  end

  test "the editor offers the repeat settings" do
    get new_communication_path
    assert_response :success
    assert_select ".brief-recurrence select[name='communication[recurrence_attributes][frequency]']"
  end

  test "an invalid rule is rejected" do
    assert_no_difference -> { Communication.count } do
      post communications_path, params: {
        communication: {
          title_fr: "Facing", body_fr: "x", format: "task",
          recurrence_attributes: { frequency: "weekly" }
        },
        org_unit_ids: [ @brand.store.id ],
        commit: "send"
      }
    end
    assert_response :unprocessable_entity
  end

  test "HQ can stop a series without touching work in flight" do
    brief = create_recurring
    delivery = brief.deliveries.first

    post stop_recurrence_communication_path(brief)

    assert_redirected_to communication_path(brief)
    assert_not brief.reload.recurrence_active?
    assert_equal "pending", delivery.reload.status
  end

  test "another tenant cannot stop a series" do
    brief = create_recurring
    other = build_brand("recurring-intruder")
    delete logout_path
    sign_in other.hq

    post stop_recurrence_communication_path(brief)

    assert_response :not_found
    assert brief.reload.recurrence_active?
  end

  test "the store inbox lists only the current instance" do
    brief = create_recurring
    brief.deliveries.first.complete!
    occurrence = Vazivo::Recurrence.spawn!(brief, today: brief.recurrence_next_on)

    delete logout_path
    sign_in @brand.store_user
    get inbox_index_path

    assert_response :success
    assert_select "a[href=?]", inbox_path(occurrence.deliveries.first)
    assert_select "a[href=?]", inbox_path(brief.deliveries.first), count: 0
  end

  private

  def create_recurring
    brief = @brand.tenant.communications.create!(
      author: @brand.hq, title_fr: "Facing", body_fr: "Check.", format: "task", status: "draft",
      recurrence_rule: { "frequency" => "daily" }
    )
    brief.send_to!([ @brand.store.id ])
    brief.reload
  end
end
