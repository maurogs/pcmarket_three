class AddSettingsToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :returns_policy, :text
    add_column :stores, :shipping_policy, :text
    add_column :stores, :default_shipping_cents, :integer, default: 0, null: false
    add_column :stores, :free_shipping_threshold_cents, :integer
  end
end
