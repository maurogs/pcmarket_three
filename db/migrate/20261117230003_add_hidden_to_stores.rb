class AddHiddenToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :hidden, :boolean, null: false, default: false
  end
end
