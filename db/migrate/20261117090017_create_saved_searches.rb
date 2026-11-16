class CreateSavedSearches < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_searches do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :query
      t.references :category, foreign_key: true
      t.jsonb :filters, null: false, default: {}
      t.boolean :email_alerts, null: false, default: true
      t.datetime :last_notified_at

      t.timestamps
    end
  end
end
