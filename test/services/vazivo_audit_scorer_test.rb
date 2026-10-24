require "test_helper"

class VazivoAuditScorerTest < ActiveSupport::TestCase
  setup do
    @brand = build_brand("audit-score", features: { morocco_ops: true })
    @tenant = @brand.tenant
    @brief = @tenant.communications.create!(
      author: @brand.hq, title_fr: "Audit rayon", body_fr: "Corps", format: "task", status: "draft"
    )
    @q1 = @brief.communication_questions.create!(
      position: 0, question_type: "single_choice", title_fr: "Facing OK?",
      options: [
        { "label_fr" => "Oui", "correct" => true },
        { "label_fr" => "Non" }
      ]
    )
    @q2 = @brief.communication_questions.create!(
      position: 1, question_type: "single_choice", title_fr: "Prix OK?",
      options: [
        { "label_fr" => "Oui", "correct" => true },
        { "label_fr" => "Non" }
      ]
    )
    @brief.send_to!([ @brand.store.id ])
    @delivery = @brief.deliveries.first
  end

  test "maps score percent to conforme improve non_conforme" do
    assert_equal "conforme", Vazivo::AuditScorer.verdict_for(80)
    assert_equal "improve", Vazivo::AuditScorer.verdict_for(50)
    assert_equal "non_conforme", Vazivo::AuditScorer.verdict_for(49)
  end

  test "scores correct choice answers and auto-applies verdict on complete" do
    @delivery.save_answers!(
      @q1.id.to_s => { "text" => "Oui" },
      @q2.id.to_s => { "text" => "Oui" }
    )
    result = Vazivo::AuditScorer.call(@delivery)
    assert_equal 100, result.score
    assert_equal "conforme", result.verdict

    Current.set(user: @brand.store_user) do
      @delivery.complete!
    end
    @delivery.reload
    assert_equal 100, @delivery.score
    assert_equal "conforme", @delivery.verdict
    assert @delivery.delivery_events.where(kind: "verdict").exists?
  end

  test "partial score yields improve and historical audits are queryable by score" do
    @delivery.save_answers!(
      @q1.id.to_s => { "text" => "Oui" },
      @q2.id.to_s => { "text" => "Non" }
    )
    Current.set(user: @brand.store_user) do
      @delivery.complete!
    end
    @delivery.reload
    assert_equal 50, @delivery.score
    assert_equal "improve", @delivery.verdict
    assert_includes Delivery.where(score: 50), @delivery
  end

  test "does not overwrite a manual verdict" do
    @delivery.save_answers!(@q1.id.to_s => { "text" => "Oui" }, @q2.id.to_s => { "text" => "Oui" })
    @delivery.apply_verdict!("improve", note: "Manual", by: @brand.hq)
    Current.set(user: @brand.store_user) do
      @delivery.update!(status: "pending", completed_at: nil, awareness: "in_progress")
      @delivery.complete!
    end
    assert_equal "improve", @delivery.reload.verdict
    assert_equal 100, @delivery.score
  end
  test "weighted choice scoring prioritizes high impact answers" do
    @q1.update_column(:weight, 3)
    @delivery.save_answers!(@q1.id.to_s => { "text" => "Oui" }, @q2.id.to_s => { "text" => "Non" })
    result = Vazivo::AuditScorer.call(@delivery)
    assert_equal 75, result.score
    assert_equal 3, result.earned
    assert_equal 4, result.possible
  end

  test "weighted completion keeps legacy defaults and counts unanswered weight" do
    @q1.update_columns(question_type: "number", options: [], weight: 3)
    @q2.update_columns(question_type: "date", options: [])
    @delivery.save_answers!(@q1.id.to_s => { "text" => "0" })
    assert_equal 75, Vazivo::AuditScorer.call(@delivery).score
    answer = @delivery.delivery_answers.first
    answer.value = { "text" => "NaN" }
    assert_not answer.valid?
  end

  test "rating earns proportional credit and NA excludes its weight" do
    @q1.update_columns(question_type: "rating", options: [], weight: 3)
    @q2.update_columns(question_type: "yes_no_na", options: [], weight: 7)
    @delivery.save_answers!(@q1.id.to_s => { "text" => "4" }, @q2.id.to_s => { "text" => "na" })
    result = Vazivo::AuditScorer.call(@delivery)
    assert_equal 80, result.score
    assert_equal 3, result.possible
    @delivery.save_answers!(@q2.id.to_s => { "text" => "no" })
    assert_equal 24, Vazivo::AuditScorer.call(@delivery).score
    @delivery.save_answers!(@q2.id.to_s => { "text" => "yes" })
    assert_equal 94, Vazivo::AuditScorer.call(@delivery).score
  end

  test "all NA yields no verdict rather than a perfect audit" do
    [ @q1, @q2 ].each { |q| q.update_columns(question_type: "yes_no_na", options: []) }
    @delivery.save_answers!(@q1.id.to_s => { "text" => "na" }, @q2.id.to_s => { "text" => "na" })
    result = Vazivo::AuditScorer.call(@delivery)
    assert_nil result.score
    assert_nil result.verdict
    assert_equal 0, result.possible
  end
end
