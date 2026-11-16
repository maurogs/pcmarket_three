class CreateSpecAttributes < ActiveRecord::Migration[8.1]
  def change
    create_table :spec_attributes do |t|
      t.string :key, null: false
      t.jsonb :names, null: false, default: {}
      t.integer :input_type, null: false, default: 0
      t.string :unit
      t.boolean :filterable, null: false, default: true
      t.integer :position, null: false, default: 0
      t.string :group

      t.timestamps
    end

    add_index :spec_attributes, :key, unique: true
  end
end
