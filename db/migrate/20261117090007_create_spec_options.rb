class CreateSpecOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :spec_options do |t|
      t.references :spec_attribute, null: false, foreign_key: true
      t.string :value, null: false
      t.jsonb :names, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.boolean :popular, null: false, default: false

      t.timestamps
    end

    add_index :spec_options, [ :spec_attribute_id, :value ], unique: true
  end
end
