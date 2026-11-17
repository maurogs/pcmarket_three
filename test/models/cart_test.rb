require "test_helper"

class CartTest < ActiveSupport::TestCase
  test "for_user returns the same cart for the user on every call" do
    user = users(:two)
    cart = Cart.for_user(user)
    assert_equal user, cart.user
    assert_equal cart.id, Cart.for_user(user.reload).id
  end

  test "for_user never returns another user's cart" do
    mine = Cart.for_user(users(:two))
    assert_nil Cart.where(id: mine.id).where(user: users(:one)).first
  end

  test "guest carts get a random token and no user" do
    cart = Cart.create!
    assert_nil cart.user
    assert_match(/\A[0-9A-Za-z]{24}\z/, cart.token)
    refute_equal Cart.create!.token, cart.token
  end

  test "cart items are destroyed with the cart" do
    cart = Cart.create!
    cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)
    assert_difference -> { CartItem.count }, -1 do
      cart.destroy!
    end
  end

  test "subtotal_cents sums price times quantity" do
    cart = Cart.create!
    cart.cart_items.create!(listing: listings(:gigabyte), quantity: 2)
    cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_equal listings(:gigabyte).price_cents * 2 + listings(:as_new).price_cents, cart.subtotal_cents
  end
end
