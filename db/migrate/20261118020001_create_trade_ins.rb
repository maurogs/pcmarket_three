class CreateTradeIns < ActiveRecord::Migration[8.1]
  def change
    create_table :trade_ins do |t|
      # Quoter identity: null while the quote is anonymous (status quoted),
      # set when the visitor signs in and accepts.
      t.references :user, foreign_key: true
      t.integer :component_type, null: false
      t.string :model, null: false
      t.integer :condition, null: false
      t.boolean :has_box, null: false, default: true
      t.integer :offered_cents, null: false
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :trade_ins, :status
    add_index :trade_ins, :expires_at
  end
end
