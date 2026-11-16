class AddLocationToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :city, :string
    add_column :stores, :region, :string
  end
end
