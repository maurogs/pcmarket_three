class AddReservationFieldsToListings < ActiveRecord::Migration[8.1]
  def change
    add_column :listings, :reserved_until, :datetime
    add_reference :listings, :reserved_for, null: true, foreign_key: { to_table: :users }
  end
end
