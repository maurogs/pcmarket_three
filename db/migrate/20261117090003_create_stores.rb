class CreateStores < ActiveRecord::Migration[8.1]
  def change
    create_table :stores do |t|
      t.references :user, null: false, index: { unique: true }, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.integer :store_type, null: false, default: 0
      t.boolean :verified, null: false, default: false
      t.string :vat_number
      t.boolean :vacation_mode, null: false, default: false
      t.boolean :allow_offers_default, null: false, default: true
      t.integer :listings_count, null: false, default: 0
      t.integer :sales_count, null: false, default: 0
      t.decimal :rating_average, precision: 3, scale: 2, null: false, default: "0.00"
      t.integer :reviews_count, null: false, default: 0
      t.integer :followers_count, null: false, default: 0

      t.timestamps
    end

    add_index :stores, :slug, unique: true
  end
end
