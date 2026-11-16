class CreateOrders < ActiveRecord::Migration[8.1]
  def up
    create_table :orders do |t|
      t.references :buyer, null: false, foreign_key: { to_table: :users }
      t.references :seller, null: false, foreign_key: { to_table: :users }
      t.string :number, null: false
      t.integer :status, null: false, default: 0
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :commission_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "EUR"
      t.jsonb :shipping_address
      t.string :payment_provider
      t.string :payment_reference
      t.string :tracking_number
      t.string :carrier
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.datetime :buyer_protection_until

      t.timestamps
    end

    add_index :orders, :number, unique: true
    add_index :orders, [ :buyer_id, :status ]
    add_index :orders, [ :seller_id, :status ]

    # Backs the human-readable PCM-YYYY-NNNNNN order numbers.
    execute "CREATE SEQUENCE order_number_seq START 1"
  end

  def down
    execute "DROP SEQUENCE IF EXISTS order_number_seq"
    drop_table :orders
  end
end
