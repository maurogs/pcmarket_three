class AddKindAndOfferToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :kind, :integer, default: 0, null: false
    add_reference :messages, :offer, null: true, foreign_key: true
  end
end
