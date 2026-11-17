class AddLifecycleFieldsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :paid_at, :datetime
    add_column :orders, :completed_at, :datetime
    add_column :orders, :cancelled_at, :datetime
    add_column :orders, :checkout_token, :string
    add_index :orders, :checkout_token
    add_index :orders, :status
  end
end
