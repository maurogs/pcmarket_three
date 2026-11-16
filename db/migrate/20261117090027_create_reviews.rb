class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :order, null: false, index: { unique: true }, foreign_key: true
      t.references :reviewer, null: false, foreign_key: { to_table: :users }
      t.references :store, foreign_key: true
      t.references :seller, foreign_key: { to_table: :users }
      t.integer :rating, null: false
      t.text :body

      t.timestamps
    end
  end
end
