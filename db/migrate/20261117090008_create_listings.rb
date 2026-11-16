class CreateListings < ActiveRecord::Migration[8.1]
  def change
    create_table :listings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string :country_code, null: false, default: "ES"
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :price_cents, null: false
      t.integer :original_price_cents
      t.string :currency, null: false, default: "EUR"
      t.integer :condition, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.text :rejection_reason
      t.integer :quantity, null: false, default: 1
      t.jsonb :specs, null: false, default: {}
      t.boolean :shipping_available, null: false, default: true
      t.boolean :local_pickup, null: false, default: false
      t.string :city
      t.string :region
      t.string :postal_code
      t.integer :shipping_price_cents, null: false, default: 0
      t.boolean :free_shipping, null: false, default: false
      t.boolean :allow_offers
      t.datetime :featured_until
      t.datetime :published_at
      t.datetime :sold_at
      t.integer :views_count, null: false, default: 0
      t.integer :favorites_count, null: false, default: 0
      t.integer :performance_score
      t.tsvector :tsv

      t.timestamps
    end

    add_index :listings, :slug, unique: true
    add_index :listings, [ :status, :published_at ]
    add_index :listings, [ :category_id, :status ]
    add_index :listings, [ :user_id, :status ]
    add_index :listings, :price_cents
    add_index :listings, :featured_until
    add_index :listings, :specs, using: :gin
    add_index :listings, :tsv, using: :gin, name: "index_listings_on_tsv"
  end
end
