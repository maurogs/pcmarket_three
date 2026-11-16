class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|
      t.string :code, null: false
      t.string :name_key, null: false
      t.string :currency, null: false, default: "EUR"
      t.string :default_locale, null: false, default: "es"
      t.boolean :enabled, null: false, default: false
      t.decimal :vat_rate, precision: 5, scale: 2, null: false, default: "0.00"

      t.timestamps
    end

    add_index :countries, :code, unique: true
  end
end
