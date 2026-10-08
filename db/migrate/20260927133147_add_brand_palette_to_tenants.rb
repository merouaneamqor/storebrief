class AddBrandPaletteToTenants < ActiveRecord::Migration[8.1]
  def change
    change_table :tenants, bulk: true do |t|
      t.string :secondary_color, null: false, default: "#1e4b7a"
      t.string :primary_deep_color, null: false, default: "#084c3f"
      t.string :primary_soft_color, null: false, default: "#d7efe7"
      t.string :secondary_soft_color, null: false, default: "#e0ecf8"
      t.string :text_color, null: false, default: "#102033"
      t.string :text_muted_color, null: false, default: "#5c6d7c"
      t.string :bg_color, null: false, default: "#f4f1ea"
      t.string :bg_deep_color, null: false, default: "#efeae2"
      t.string :surface_color, null: false, default: "#fffcf7"
      t.string :line_color, null: false, default: "#ddd6cb"
      t.string :sidebar_color, null: false, default: "#0f172a"
      t.string :sidebar_text_color, null: false, default: "#e2e8f0"
      t.string :warn_color, null: false, default: "#9a3412"
      t.string :warn_soft_color, null: false, default: "#ffedd5"
    end
  end
end
