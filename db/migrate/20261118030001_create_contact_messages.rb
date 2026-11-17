class CreateContactMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :contact_messages do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.string :locale, null: false, default: "es"

      t.timestamps
    end

    add_index :contact_messages, :created_at
  end
end
