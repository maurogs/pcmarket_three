class CreateOrderNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :order_notes do |t|
      t.references :order, null: false, foreign_key: true, index: true
      t.references :admin, null: false, foreign_key: { to_table: :users }, index: true
      t.text :body, null: false

      t.timestamps
    end
  end
end
