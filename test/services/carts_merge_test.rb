require "test_helper"

class CartsMergeTest < ActiveSupport::TestCase
  test "guest items move into the user cart on sign in" do
    user = users(:two)
    user_cart = Cart.for_user(user)
    user_cart.cart_items.create!(listing: listings(:as_new), quantity: 1)

    guest_cart = Cart.create!
    listings(:gigabyte).update!(quantity: 5)
    guest_cart.cart_items.create!(listing: listings(:gigabyte), quantity: 2)
    guest_cart.cart_items.create!(listing: listings(:featured), quantity: 1)

    result = Carts::Merge.call(from: guest_cart, to: user_cart)
    assert_equal 2, result.merged_count
    assert_equal 0, result.discarded_count
    assert_not Cart.exists?(guest_cart.id)
    assert_equal [ 1, 1, 2 ], user_cart.cart_items.reload.pluck(:quantity).sort
    assert user_cart.cart_items.exists?(listing: listings(:gigabyte))
  end

  test "quantities are capped at the listing quantity during merge" do
    user = users(:two)
    user_cart = Cart.for_user(user)
    listing = listings(:gigabyte)
    listing.update!(quantity: 3)
    user_cart.cart_items.create!(listing: listing, quantity: 2)

    guest_cart = Cart.create!
    guest_cart.cart_items.create!(listing: listing, quantity: 3)

    result = Carts::Merge.call(from: guest_cart, to: user_cart)
    assert_equal 3, user_cart.cart_items.find_by(listing: listing).quantity
    assert_equal 1, result.merged_count
    assert_equal 0, result.discarded_count
  end

  test "listings that stopped being purchasable are discarded, not carried over" do
    user_cart = Cart.for_user(users(:admin))
    guest_cart = Cart.create!
    guest_cart.cart_items.create!(listing: listings(:sold), quantity: 1)

    result = Carts::Merge.call(from: guest_cart, to: user_cart)
    assert_equal 0, result.merged_count
    assert_equal 1, result.discarded_count
    assert_empty user_cart.cart_items.reload
  end

  test "merging a user cart into itself is a no-op" do
    user_cart = Cart.for_user(users(:two))
    user_cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)
    result = Carts::Merge.call(from: user_cart, to: user_cart)
    assert_equal [ 0, 0 ], [ result.merged_count, result.discarded_count ]
    assert Cart.exists?(user_cart.id)
    assert_equal 1, user_cart.cart_items.reload.count
  end

  test "a missing guest cart is a no-op" do
    user_cart = Cart.for_user(users(:two))
    result = Carts::Merge.call(from: nil, to: user_cart)
    assert_equal [ 0, 0 ], [ result.merged_count, result.discarded_count ]
    result = Carts::Merge.call(from: Cart.create!, to: nil)
    assert_equal [ 0, 0 ], [ result.merged_count, result.discarded_count ]
  end
end
