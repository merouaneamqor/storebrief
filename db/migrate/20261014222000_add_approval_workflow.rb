class AddApprovalWorkflow < ActiveRecord::Migration[8.1]
  def change
    add_column :communications, :requires_approval, :boolean, null: false, default: false
    add_column :communication_templates, :requires_approval, :boolean, null: false, default: false
  end
end
