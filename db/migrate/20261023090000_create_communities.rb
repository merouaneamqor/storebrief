class CreateCommunities < ActiveRecord::Migration[8.1]
  def change
    create_table :communities do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :org_unit, foreign_key: true
      t.string :title_fr, null: false
      t.string :title_ar
      t.string :audience_role
      t.timestamps
    end
    create_table :community_posts do |t|
      t.references :community, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    create_table :community_comments do |t|
      t.references :community_post, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
  end
end
