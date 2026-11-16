class AddListingSearchTrigger < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION listings_tsv_trigger() RETURNS trigger AS $$
      BEGIN
        NEW.tsv :=
          setweight(to_tsvector('simple', coalesce(NEW.title, '')), 'A') ||
          setweight(to_tsvector('simple', coalesce(NEW.description, '')), 'B');
        RETURN NEW;
      END
      $$ LANGUAGE plpgsql;
    SQL

    execute <<~SQL
      CREATE TRIGGER trg_listings_tsv
      BEFORE INSERT OR UPDATE OF title, description ON listings
      FOR EACH ROW EXECUTE FUNCTION listings_tsv_trigger();
    SQL

    # Backfill existing rows (table is empty on a fresh DB, harmless otherwise).
    execute <<~SQL
      UPDATE listings
      SET tsv = setweight(to_tsvector('simple', coalesce(title, '')), 'A') ||
                setweight(to_tsvector('simple', coalesce(description, '')), 'B');
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS trg_listings_tsv ON listings"
    execute "DROP FUNCTION IF EXISTS listings_tsv_trigger()"
  end
end
