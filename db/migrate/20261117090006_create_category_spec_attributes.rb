class CreateCategorySpecAttributes < ActiveRecord::Migration[8.1]
  def change
    create_table :category_spec_attributes do |t|
      t.references :category, null: false, foreign_key: true
      t.references :spec_attribute, null: false, foreign_key: true
      t.boolean :required, null: false, default: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :category_spec_attributes, [ :category_id, :spec_attribute_id ], unique: true
  end
end
