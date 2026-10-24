class AddAudienceStoreTagsToKbArticles < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_articles, :audience_store_tags, :string, array: true, null: false, default: []
    add_index :kb_articles, :audience_store_tags, using: :gin, name: "index_kb_articles_on_audience_store_tags"
  end
end
