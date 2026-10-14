class CreateKbArticlesAndCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :kb_categories do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :parent, foreign_key: { to_table: :kb_categories, on_delete: :nullify }
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :description_fr
      t.text :description_ar
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [ :tenant_id, :parent_id, :position ], name: "index_kb_categories_on_tenant_parent_position"
      t.index [ :tenant_id, :title_fr ], name: "index_kb_categories_on_tenant_id_and_title_fr"
    end

    create_table :kb_articles do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :kb_category, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :body_fr, null: false, default: ""
      t.text :body_ar
      t.string :publish_state, null: false, default: "draft"
      t.integer :version, null: false, default: 1
      t.datetime :published_at
      t.timestamps
      t.index [ :tenant_id, :publish_state ], name: "index_kb_articles_on_tenant_id_and_publish_state"
      t.index [ :tenant_id, :kb_category_id ], name: "index_kb_articles_on_tenant_id_and_kb_category_id"
      t.index [ :tenant_id, :title_fr ], name: "index_kb_articles_on_tenant_id_and_title_fr"
    end

    create_table :kb_article_versions do |t|
      t.references :kb_article, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :version, null: false
      t.string :title_fr, null: false
      t.string :title_ar
      t.text :body_fr, null: false, default: ""
      t.text :body_ar
      t.string :publish_state, null: false
      t.datetime :published_at
      t.timestamps
      t.index [ :kb_article_id, :version ], name: "index_kb_article_versions_on_article_and_version", unique: true
    end
  end
end
