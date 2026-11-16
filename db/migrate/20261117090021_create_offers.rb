class CreateOffers < ActiveRecord::Migration[8.1]
  def change
    create_table :offers do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.integer :amount_cents, null: false
      t.integer :status, null: false, default: 0
      t.datetime :expires_at

      t.timestamps
    end

    add_index :offers, [ :listing_id, :status ]
  end
end
