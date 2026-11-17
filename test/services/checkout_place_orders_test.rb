require "test_helper"

class CheckoutPlaceOrdersTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @buyer = users(:admin) # buys from both sellers
    @cart = Cart.for_user(@buyer)
    @address = addresses(:one)
    @token = SecureRandom.base58(24)
    Flipper.disable(:commissions)
  end

  def place(**opts)
    Checkout::PlaceOrders.call(
      buyer: @buyer, cart: @cart, address: @address, checkout_token: @token, **opts
    )
  end

  test "creates one order per seller with recomputed totals" do
    listings(:featured).update!(quantity: 5)
    @cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)  # seller one, 599.99
    @cart.cart_items.create!(listing: listings(:featured), quantity: 2)  # seller one, 650.00 each
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)   # seller two, 330.00

    result = place
    assert_predicate result, :success?
    assert_equal [ users(:one).id, users(:two).id ].sort, result.orders.map(&:seller_id).sort
    assert_equal 2, result.orders.count

    big = result.orders.find { |o| o.seller_id == users(:one).id }
    assert_equal 59_999 + 2 * 65_000, big.subtotal_cents
    assert_equal 0, big.shipping_cents  # fixture listings ship free
    assert_equal 0, big.commission_cents
    assert_equal big.subtotal_cents, big.total_cents
    assert_predicate big, :pending_payment?
    assert_nil big.buyer_protection_until
    assert_equal 2, big.order_items.count
    assert_equal @address.to_snapshot, big.shipping_address

    assert_predicate @cart.cart_items.reload, :empty?
  end

  test "commission is charged when the flag is on and zero when off" do
    listings(:as_new).update!(quantity: 5)
    Flipper.disable(:commissions)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_equal 0, place.orders.first.commission_cents

    Flipper.enable(:commissions)
    Setting.set("commission_percent", "6")
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    order = place(checkout_token: SecureRandom.base58(24)).orders.first

    assert_equal 1_980, order.commission_cents # 6% of 330.00
    assert_equal 33_000 + 1_980, order.total_cents
    assert_equal 33_000, order.net_revenue_cents
  ensure
    Flipper.disable(:commissions)
  end

  test "pickups skip shipping only for sellers that allow it" do
    listings(:as_new).update!(local_pickup: true, shipping_price_cents: 499)
    listings(:gigabyte).update!(local_pickup: false, shipping_price_cents: 799)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    @cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)

    result = place(pickup_seller_ids: [ users(:two).id, users(:one).id, "junk" ])
    by_seller = result.orders.index_by(&:seller_id)
    assert_equal 0, by_seller[users(:two).id].shipping_cents
    assert_equal 799, by_seller[users(:one).id].shipping_cents
  end

  test "the last unit sold marks the listing sold; partial stock is decremented" do
    listings(:as_new).update!(quantity: 5)
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 3)
    @cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1) # quantity 1

    result = place
    as_new = listings(:as_new).reload
    gigabyte = listings(:gigabyte).reload

    assert_equal 2, as_new.quantity
    assert_predicate as_new, :approved?
    assert_predicate gigabyte, :sold? # last unit gone
    assert_equal 0, gigabyte.quantity
    assert_not_nil gigabyte.sold_at
    assert_equal 2, result.orders.count
  end

  test "a listing sold while the checkout runs fails the whole checkout without orders" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    @cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)

    # Simulate a concurrent sale landing between the cart read and the
    # locked re-check: the row flips to sold exactly when PlaceOrders
    # locks it.
    target = listings(:gigabyte).id
    real_find = Listing.method(:find)
    Listing.singleton_class.define_method(:find) do |*args|
      row = real_find.call(*args)
      if row.is_a?(Listing) && row.id == target
        Listing.where(id: target).update_all(status: Listing.statuses[:sold])
        row = row.reload
      end
      row
    end

    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      result = place
      assert_not_predicate result, :success?
      assert_equal :not_purchasable, result.error
    end
  ensure
    Listing.singleton_class.remove_method(:find)
  end

  test "re-validates the cart against the locked rows" do
    # A cart whose only item is already sold has nothing orderable.
    @cart.cart_items.create!(listing: listings(:sold), quantity: 1)
    result = place
    assert_equal :empty_cart, result.error
    assert_no_difference [ "Order.count", "OrderItem.count" ] do
      place(checkout_token: SecureRandom.base58(24))
    end

    @cart.cart_items.delete_all
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 99)
    assert_equal :quantity_exceeded, place.error

    @cart.cart_items.delete_all
    @cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)
    own_cart = Cart.for_user(users(:one))
    own_cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)
    own = Checkout::PlaceOrders.call(buyer: users(:one), cart: own_cart, address: @address,
                                     checkout_token: SecureRandom.base58(24))
    assert_equal :own_listing, own.error

    stores(:two).update!(vacation_mode: true)
    @cart.cart_items.delete_all
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_equal :vacation, place(checkout_token: SecureRandom.base58(24)).error
  end

  test "replaying the same checkout token returns the orders already placed" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    before = Order.count
    first = place
    assert_predicate first, :success?

    # Double submit: cart is already empty, but the token must replay.
    replay = place
    assert_predicate replay, :success?
    assert_equal first.orders.map(&:id), replay.orders.map(&:id)
    assert_equal before + 1, Order.count
  end

  test "blank tokens, missing addresses and empty carts are refused" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_equal :invalid_token, place(checkout_token: "").error
    assert_equal :invalid_address, place(address: nil).error
    assert_equal :empty_cart, place(cart: Cart.for_user(users(:banned))).error
  end

  test "notify both parties and send e-mails when orders are placed" do
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    assert_difference -> { Notification.count }, 2 do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 2 do
        perform_enqueued_jobs do
          assert_predicate place, :success?
        end
      end
    end
    kinds = Notification.order(:id).last(2).pluck(:kind)
    assert_equal %w[order_placed order_confirmed], kinds
  end
end
