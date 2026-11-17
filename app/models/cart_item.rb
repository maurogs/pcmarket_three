class CartItem < ApplicationRecord
  belongs_to :cart
  belongs_to :listing

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :listing_id, uniqueness: { scope: :cart_id }

  # NOTE: there is deliberately no "listing must be approved" validation:
  # items stay in the cart when a listing is sold/archived/rejected after
  # being added, so the cart page can grey them out with a notice instead
  # of silently dropping them (Carts::Summary flags them stale). Purchase
  # rules live in Carts::AddItem and Checkout::PlaceOrders.
  def stale?(for_user: nil)
    !listing.purchasable_by?(for_user)
  end
end
