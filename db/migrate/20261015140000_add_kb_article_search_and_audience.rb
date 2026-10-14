class AddKbArticleSearchAndAudience < ActiveRecord::Migration[8.1]
  def up
    add_column :kb_articles, :audience_roles, :string, array: true, null: false, default: []
    add_index :kb_articles, :audience_roles, using: :gin, name: "index_kb_articles_on_audience_roles"

    add_column :kb_articles, :search_vector, :tsvector
    add_index :kb_articles, :search_vector, using: :gin, name: "index_kb_articles_on_search_vector"

    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION kb_articles_search_vector_update() RETURNS trigger AS $$
      BEGIN
        NEW.search_vector :=
          setweight(to_tsvector('simple', coalesce(NEW.title_fr, '')), 'A') ||
          setweight(to_tsvector('simple', coalesce(NEW.title_ar, '')), 'A') ||
          setweight(to_tsvector('simple', coalesce(NEW.body_fr, '')), 'B') ||
          setweight(to_tsvector('simple', coalesce(NEW.body_ar, '')), 'B');
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL.squish
      CREATE TRIGGER kb_articles_search_vector_trigger
      BEFORE INSERT OR UPDATE OF title_fr, title_ar, body_fr, body_ar
      ON kb_articles
      FOR EACH ROW
      EXECUTE FUNCTION kb_articles_search_vector_update();
    SQL

    execute <<~SQL.squish
      UPDATE kb_articles SET search_vector =
        setweight(to_tsvector('simple', coalesce(title_fr, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(title_ar, '')), 'A') ||
        setweight(to_tsvector('simple', coalesce(body_fr, '')), 'B') ||
        setweight(to_tsvector('simple', coalesce(body_ar, '')), 'B');
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS kb_articles_search_vector_trigger ON kb_articles;"
    execute "DROP FUNCTION IF EXISTS kb_articles_search_vector_update();"
    remove_index :kb_articles, name: "index_kb_articles_on_search_vector"
    remove_column :kb_articles, :search_vector
    remove_index :kb_articles, name: "index_kb_articles_on_audience_roles"
    remove_column :kb_articles, :audience_roles
  end
end
