class CreateModerationEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :moderation_events do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :admin, null: false, foreign_key: { to_table: :users }
      t.integer :action, null: false
      t.text :note

      t.timestamps
    end
  end
end
