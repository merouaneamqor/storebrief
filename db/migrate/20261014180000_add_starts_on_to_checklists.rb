class AddStartsOnToChecklists < ActiveRecord::Migration[8.1]
  def change
    add_column :checklists, :starts_on, :date
  end
end
