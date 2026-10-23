class CreateFeedEngagement < ActiveRecord::Migration[8.1]
  def change
    create_table :feed_posts do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :org_unit, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end
    create_table :feed_comments do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.text :body, null: false
      t.datetime :removed_at
      t.timestamps
    end
    create_table :feed_reactions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :subject, polymorphic: true, null: false
      t.string :kind, null: false
      t.timestamps
    end
    add_index :feed_reactions, [ :subject_type, :subject_id, :user_id ], unique: true
  end
end
