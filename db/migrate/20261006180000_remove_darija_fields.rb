class RemoveDarijaFields < ActiveRecord::Migration[8.1]
  def change
    remove_column :playbooks, :title_darija, :string
    remove_column :playbooks, :description_darija, :text

    remove_column :communications, :title_darija, :string
    remove_column :communications, :body_darija, :text

    remove_column :checklists, :title_darija, :string
    remove_column :checklists, :description_darija, :text

    remove_column :checklist_items, :title_darija, :string
  end
end
