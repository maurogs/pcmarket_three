class EnablePgTrgm < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
    add_index :listings, :title, using: :gin, opclass: :gin_trgm_ops,
                name: "index_listings_title_trgm"
  end
end
