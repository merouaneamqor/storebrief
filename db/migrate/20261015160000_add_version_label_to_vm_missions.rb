class AddVersionLabelToVmMissions < ActiveRecord::Migration[8.1]
  def change
    add_column :vm_missions, :version_label, :string
  end
end
