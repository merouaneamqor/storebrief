require "test_helper"

class AuditHistoryTest < ActionDispatch::IntegrationTest
  setup do
    host! "localhost"
    @brand = build_brand("audit-history-ui", features: { morocco_ops: true })
    @tenant = @brand.tenant
    @store = @brand.store
    brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Audit rayon", body_fr: "Corps", format: "task", status: "draft"
    )
    brief.communication_questions.create!(
      position: 0, question_type: "single_choice", title_fr: "Facing?",
      options: [ { "label_fr" => "Oui", "correct" => true }, { "label_fr" => "Non" } ]
    )
    brief.send_to!([ @store.id ])
    delivery = brief.deliveries.first
    delivery.update!(
      status: "completed", completed_at: Time.current, score: 80, verdict: "conforme",
      validated_at: Time.current, validated_by: @brand.hq
    )
  end

  test "hq sees store history region comparison and csv export" do
    sign_in(@brand.hq)

    get audit_history_path
    assert_response :success
    assert_match I18n.t("morocco.audit_history.title", locale: :en), response.body
    assert_match I18n.t("morocco.audit_history.region_comparison", locale: :en), response.body
    assert_match I18n.t("morocco.audit_history.history_list", locale: :en), response.body
    assert_match "Audit rayon", response.body
    assert_match "80%", response.body
    assert_match "Casa", response.body

    get audit_history_path(store_id: @store.id)
    assert_response :success
    assert_match I18n.t("morocco.audit_history.store_history", store: @store.name, locale: :en), response.body

    get audit_history_path(format: :csv)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.body, "Audit rayon"
    assert_includes response.body, "Maarif"
  end

  test "store user cannot open audit history" do
    sign_in(@brand.store_user)
    get audit_history_path
    assert_redirected_to app_root_path
  end

  test "locale keys exist without em dashes" do
    %i[en fr es ar].each do |locale|
      copy = I18n.t("morocco.audit_history", locale: locale)
      assert_kind_of Hash, copy
      assert_no_em_dash(copy)
    end
  end

  private

  def assert_no_em_dash(value)
    case value
    when Hash
      value.each_value { |nested| assert_no_em_dash(nested) }
    when String
      refute_includes value, "—"
      refute_includes value, "–"
    end
  end
end
