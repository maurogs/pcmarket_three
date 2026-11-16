class CreateLegalPages < ActiveRecord::Migration[8.1]
  def change
    create_table :legal_pages do |t|
      t.string :country_code, null: false, default: "ES"
      t.string :locale, null: false, default: "es"
      t.string :slug, null: false
      t.string :title, null: false
      t.text :body
      t.boolean :published, null: false, default: false

      t.timestamps
    end

    add_index :legal_pages, [ :country_code, :locale, :slug ], unique: true
  end
end
