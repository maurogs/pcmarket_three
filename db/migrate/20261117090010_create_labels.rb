class CreateLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :labels do |t|
      t.string :slug, null: false
      t.jsonb :names, null: false, default: {}
      t.string :color

      t.timestamps
    end

    add_index :labels, :slug, unique: true
  end
end
