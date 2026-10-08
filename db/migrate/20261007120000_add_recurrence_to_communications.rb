class AddRecurrenceToCommunications < ActiveRecord::Migration[8.1]
  def change
    change_table :communications, bulk: true do |t|
      t.jsonb :recurrence_rule, null: false, default: {}
      t.date :recurrence_next_on
      t.references :recurrence_parent, foreign_key: { to_table: :communications, on_delete: :nullify }
      t.date :occurrence_on
    end

    add_index :communications, :recurrence_next_on, where: "recurrence_next_on IS NOT NULL",
              name: "index_communications_on_recurrence_next_on"
    add_index :communications, %i[recurrence_parent_id occurrence_on], unique: true,
              where: "recurrence_parent_id IS NOT NULL",
              name: "index_communications_on_series_occurrence"
  end
end
