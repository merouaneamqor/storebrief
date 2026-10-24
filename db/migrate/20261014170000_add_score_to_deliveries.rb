class AddScoreToDeliveries < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:deliveries, :score)

    add_column :deliveries, :score, :integer
  end
end
