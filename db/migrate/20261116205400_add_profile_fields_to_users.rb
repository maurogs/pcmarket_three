class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :username, :string, null: false
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
    add_column :users, :phone, :string
    add_column :users, :role, :integer, null: false, default: 0
    add_column :users, :locale, :string, null: false, default: "es"
    add_column :users, :country_code, :string, null: false, default: "ES"
    add_column :users, :confirmed_at, :datetime

    add_index :users, :username, unique: true
  end
end
