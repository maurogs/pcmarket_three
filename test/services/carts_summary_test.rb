require "test_helper"

class CartsSummaryTest < ActiveSupport::TestCase
  setup do
    @buyer = users(:one)
    @cart = Cart.for_user(@buyer)
  end

  test "groups cart items by seller in first-added order" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1) # seller two
    @cart.cart_items.create!(listing: listings(:featured), quantity: 1) # seller one… own item
    @cart.cart_items.create!(listing: listings(:pending), quantity: 1) # seller one

    summary = Carts::Summary.new(@cart)
    assert_equal [ users(:two).id, users(:one).id ], summary.groups.map { |g| g.seller.id }
    assert_equal 2, summary.groups.last.items.count
  end

  test "items whose listing stopped being purchasable are stale and excluded from totals" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 2)
    @cart.cart_items.create!(listing: listings(:sold), quantity: 1)

    summary = Carts::Summary.new(@cart)
    assert_predicate summary, :any_stale?
    assert_equal [ listings(:sold).id ], summary.stale_items.map { |i| i.listing.id }
    assert_equal listings(:as_new).price_cents * 2, summary.subtotal_cents
    assert_includes summary.items.map(&:listing_id), listings(:sold).id
  end

  test "totals price from the live listing row, not the price at add-to-cart time" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    listings(:as_new).update!(price_cents: 25_000) # seller dropped the price
    assert_equal 25_000, Carts::Summary.new(@cart).subtotal_cents
  end

  test "shipping is the highest shipping_price_cents of the group by default" do
    listings(:as_new).update!(shipping_price_cents: 499)
    listings(:gigabyte).update!(shipping_price_cents: 799)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1) # seller two alone

    assert_equal 499, Carts::Summary.new(@cart).groups.first.shipping_cents
  end

  test "free when every item of the group offers free shipping" do
    listings(:as_new).update!(free_shipping: true)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_equal 0, Carts::Summary.new(@cart).groups.first.shipping_cents
  end

  test "free once the group subtotal reaches the store threshold" do
    stores(:two).update!(free_shipping_threshold_cents: 30_000)
    listings(:as_new).update!(shipping_price_cents: 499)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1) # 330.00 >= 300.00

    assert_equal 0, Carts::Summary.new(@cart).groups.first.shipping_cents
  end

  test "charged while the group subtotal stays under the threshold" do
    stores(:two).update!(free_shipping_threshold_cents: 40_000)
    listings(:as_new).update!(shipping_price_cents: 499)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1) # 330.00 < 400.00

    assert_equal 499, Carts::Summary.new(@cart).groups.first.shipping_cents
  end

  test "pickup is only available when every live item of the seller allows it" do
    listings(:as_new).update!(local_pickup: true, shipping_price_cents: 499)
    listings(:gigabyte).update!(local_pickup: false, shipping_price_cents: 799)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    @cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)

    summary = Carts::Summary.new(@cart)
    seller_two, seller_one = summary.groups
    assert_predicate seller_two, :pickup_available?
    assert_not_predicate seller_one, :pickup_available?
    # Chosen pickup only zeroes groups that allow it.
    assert_equal 799, summary.shipping_cents(pickup_seller_ids: [ users(:two).id, users(:one).id ])
  end

  test "an empty cart is not orderable" do
    summary = Carts::Summary.new(@cart)
    assert_predicate summary, :empty?
    assert_not_predicate summary, :orderable?
  end

  test "a cart of only stale items is not orderable" do
    @cart.cart_items.create!(listing: listings(:sold), quantity: 1)
    assert_not_predicate Carts::Summary.new(@cart), :orderable?
  end
end
