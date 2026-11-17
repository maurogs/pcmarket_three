require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    @order = Order.create!(buyer: users(:one), seller: users(:two),
                           subtotal_cents: 33_000, currency: "EUR")
  end

  test "assigns a sequential human-readable number" do
    assert_match(/\APCM-\d{4}-\d{6}\z/, @order.number)
    other = Order.create!(buyer: users(:one), seller: users(:two),
                          subtotal_cents: 1, currency: "EUR")
    assert_not_equal @order.number, other.number
  end

  test "happy path: pending → paid → shipped → delivered → completed" do
    @order.pay!
    assert_predicate @order, :paid?
    assert_not_nil @order.paid_at

    @order.ship!(carrier: "SEUR", tracking_number: "TRK123")
    assert_predicate @order, :shipped?
    assert_equal "SEUR", @order.carrier
    assert_equal "TRK123", @order.tracking_number

    @order.mark_delivered!
    assert_predicate @order, :delivered?
    assert_not_nil @order.buyer_protection_until
    assert_operator @order.buyer_protection_until, :>, Time.current

    @order.complete!
    assert_predicate @order, :completed?
    assert_not_nil @order.completed_at
  end

  test "illegal transitions raise InvalidTransition" do
    assert_raises(Order::InvalidTransition) { @order.ship!(carrier: "SEUR") }     # not paid yet
    @order.pay!
    assert_raises(Order::InvalidTransition) { @order.mark_delivered! }            # not shipped
    assert_raises(Order::InvalidTransition) { @order.complete! }                  # not delivered
    @order.ship!(carrier: "Correos")
    assert_raises(Order::InvalidTransition) { @order.pay! }                       # already shipped
    assert_raises(Order::InvalidTransition) { @order.cancel! }                    # past paid
  end

  test "cancelling a placed order restores every listing" do
    buyer = users(:admin)
    cart = Cart.for_user(buyer)
    listings(:as_new).update!(quantity: 4)
    cart.cart_items.create!(listing: listings(:as_new), quantity: 2)
    cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)

    orders = Checkout::PlaceOrders.call(buyer: buyer, cart: cart,
                                        address: addresses(:one),
                                        checkout_token: SecureRandom.base58(24)).orders
    assert_predicate listings(:gigabyte).reload, :sold?
    assert_equal 2, listings(:as_new).reload.quantity

    orders.each(&:cancel!)

    as_new = listings(:as_new).reload
    gigabyte = listings(:gigabyte).reload
    assert_equal 4, as_new.quantity
    assert_predicate gigabyte, :approved?
    assert_equal 1, gigabyte.quantity
    assert_nil gigabyte.sold_at
  end

  test "disputes are only possible on delivered orders inside the protection window" do
    @order.pay!
    @order.ship!(carrier: "GLS")
    @order.mark_delivered!
    @order.open_dispute!
    assert_predicate @order, :disputed?

    other = Order.create!(buyer: users(:one), seller: users(:two), subtotal_cents: 1, currency: "EUR")
    other.pay!
    other.ship!(carrier: "GLS")
    other.mark_delivered!
    other.update!(buyer_protection_until: 1.second.ago)
    refute_predicate other, :protection_open?
    assert_raises(Order::InvalidTransition) { other.open_dispute! }
    assert_predicate other, :delivered?
  end

  test "step_times exposes the lifecycle timestamps" do
    assert_nil @order.step_times[:paid]
    @order.pay!
    assert_equal @order.paid_at, @order.step_times[:paid]
  end

  test "totals include shipping and commission" do
    @order.update!(shipping_cents: 499)
    @order.apply_commission!
    assert_equal 0, @order.commission_cents # commissions flag off
    Flipper.enable(:commissions)
    Setting.set("commission_percent", "10")
    @order.apply_commission!
    assert_equal 3_300, @order.commission_cents
    assert_equal 33_000 + 499 + 3_300, @order.total_cents
    assert_equal 33_000 + 499, @order.net_revenue_cents
  ensure
    Flipper.disable(:commissions)
  end
end
