class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :user, null: false, foreign_key: true
      t.string :push_token, null: false
      t.string :platform, null: false

      t.timestamps
    end

    add_index :devices, %i[user_id push_token], unique: true
  end
end
