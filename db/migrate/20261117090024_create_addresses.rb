class CreateAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :full_name, null: false
      t.string :line1, null: false
      t.string :line2
      t.string :city, null: false
      t.string :region
      t.string :postal_code, null: false
      t.string :country_code, null: false, default: "ES"
      t.string :phone
      t.boolean :default, null: false, default: false

      t.timestamps
    end
  end
end
