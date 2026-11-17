require "test_helper"

class CartsAddItemTest < ActiveSupport::TestCase
  setup do
    @buyer = users(:one)
    @cart = Cart.for_user(@buyer)
    @listing = listings(:as_new) # approved, seller two, 330 EUR
    @listing.update!(quantity: 5)
  end

  test "adds a purchasable listing from another user" do
    result = Carts::AddItem.call(cart: @cart, listing: @listing, quantity: 2)
    assert_predicate result, :success?
    item = @cart.cart_items.find_by(listing: @listing)
    assert_equal 2, item.quantity
  end

  test "merges quantities when the listing is already in the cart" do
    Carts::AddItem.call(cart: @cart, listing: @listing, quantity: 2)
    Carts::AddItem.call(cart: @cart, listing: @listing, quantity: 3)
    assert_equal 1, @cart.cart_items.where(listing: @listing).count
    assert_equal 5, @cart.cart_items.find_by(listing: @listing).quantity
  end

  test "rejects adding your own listing" do
    own = listings(:gigabyte) # seller one
    assert_equal @buyer, own.user
    result = Carts::AddItem.call(cart: @cart, listing: own, quantity: 1)
    assert_not_predicate result, :success?
    assert_equal :own_listing, result.error
  end

  test "rejects listings that are not purchasable" do
    sold = listings(:sold)
    refute sold.purchasable_by?(@buyer)
    result = Carts::AddItem.call(cart: Cart.for_user(users(:admin)), listing: sold, quantity: 1)
    assert_not_predicate result, :success?
    assert_equal :not_purchasable, result.error
    assert_empty @cart.cart_items.reload
  end

  test "rejects quantities beyond what is in stock" do
    @listing.update!(quantity: 3)
    result = Carts::AddItem.call(cart: @cart, listing: @listing, quantity: 4)
    assert_not_predicate result, :success?
    assert_equal :quantity_exceeded, result.error
  end

  test "rejects zero and negative quantities" do
    assert_equal :invalid_quantity, Carts::AddItem.call(cart: @cart, listing: @listing, quantity: 0).error
    assert_equal :invalid_quantity, Carts::AddItem.call(cart: @cart, listing: @listing, quantity: -1).error
  end

  test "rejects a buyer on vacation mode" do
    listings(:as_new).store.update!(vacation_mode: true)
    result = Carts::AddItem.call(cart: @cart, listing: @listing, quantity: 1)
    assert_not_predicate result, :success?
    assert_equal :vacation, result.error
  end

  test "nil listing is rejected" do
    result = Carts::AddItem.call(cart: @cart, listing: nil, quantity: 1)
    assert_not_predicate result, :success?
    assert_equal :not_found, result.error
  end
end
