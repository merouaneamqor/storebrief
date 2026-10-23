class AddWeightToCommunicationQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :communication_questions, :weight, :decimal, precision: 8, scale: 2, default: 1, null: false
    add_check_constraint :communication_questions, "weight > 0", name: "communication_questions_positive_weight"
  end
end
