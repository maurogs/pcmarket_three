class CreateCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :categories do |t|
      t.references :parent, foreign_key: { to_table: :categories }
      t.string :slug, null: false
      t.jsonb :names, null: false, default: {}
      t.jsonb :seo_descriptions, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :listings_count, null: false, default: 0
      t.string :icon

      t.timestamps
    end

    add_index :categories, :slug, unique: true
  end
end
