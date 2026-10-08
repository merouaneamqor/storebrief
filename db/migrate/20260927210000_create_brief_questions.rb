class CreateBriefQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :communication_questions do |t|
      t.references :communication, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :question_type, null: false, default: "short_text"
      t.string :title_fr, null: false
      t.string :title_ar
      t.boolean :required, null: false, default: false
      t.jsonb :options, null: false, default: []
      t.timestamps
    end

    add_index :communication_questions, [ :communication_id, :position ]

    create_table :delivery_answers do |t|
      t.references :delivery, null: false, foreign_key: true
      t.references :communication_question, null: false, foreign_key: true
      t.jsonb :value, null: false, default: {}
      t.timestamps
    end

    add_index :delivery_answers, [ :delivery_id, :communication_question_id ], unique: true, name: "index_delivery_answers_on_delivery_and_question"
  end
end
