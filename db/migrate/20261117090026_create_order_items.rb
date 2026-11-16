class CreateOrderItems < ActiveRecord::Migration[8.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :listing, foreign_key: { on_delete: :nullify }
      t.string :title, null: false
      t.integer :price_cents, null: false
      t.integer :quantity, null: false, default: 1

      t.timestamps
    end
  end
end
