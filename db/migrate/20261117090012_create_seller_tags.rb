class CreateSellerTags < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_tags do |t|
      t.string :slug, null: false
      t.jsonb :names, null: false, default: {}

      t.timestamps
    end

    add_index :seller_tags, :slug, unique: true
  end
end
