class CreateListingLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :listing_labels do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true

      t.timestamps
    end

    add_index :listing_labels, [ :listing_id, :label_id ], unique: true
  end
end
