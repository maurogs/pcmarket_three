class AddPriceCentsAtSaveToFavorites < ActiveRecord::Migration[8.1]
  def change
    add_column :favorites, :price_cents_at_save, :integer
  end
end
