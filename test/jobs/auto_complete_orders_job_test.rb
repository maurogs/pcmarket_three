require "test_helper"

class AutoCompleteOrdersJobTest < ActiveSupport::TestCase
  test "completes delivered orders once the buyer-protection window lapses" do
    order = create_order(status: :delivered)
    order.update!(delivered_at: 3.days.ago, buyer_protection_until: 1.day.ago)

    AutoCompleteOrdersJob.perform_now
    assert_predicate order.reload, :completed?
    assert_not_nil order.completed_at
  end

  test "leaves delivered orders whose protection window is still open" do
    order = create_order(status: :delivered)
    order.update!(delivered_at: 1.hour.ago,
                  buyer_protection_until: Order::BUYER_PROTECTION_WINDOW.from_now)

    AutoCompleteOrdersJob.perform_now
    assert_predicate order.reload, :delivered?
  end

  test "auto-cancels pending_payment orders past the payment window and restores the listings" do
    buyer = users(:admin)
    cart = Cart.for_user(buyer)
    cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1) # 1 unit left

    placed = Checkout::PlaceOrders.call(buyer: buyer, cart: cart,
                                        address: addresses(:one),
                                        checkout_token: SecureRandom.base58(24)).orders.first
    assert_predicate listings(:gigabyte).reload, :sold?

    placed.update!(created_at: (Order::AUTO_CANCEL_AFTER + 1.hour).ago)
    AutoCompleteOrdersJob.perform_now

    assert_predicate placed.reload, :cancelled?
    gigabyte = listings(:gigabyte).reload
    assert_predicate gigabyte, :approved?
    assert_equal 1, gigabyte.quantity
    assert_nil gigabyte.sold_at
  end

  test "leaves fresh pending_payment orders alone" do
    order = create_order(status: :pending_payment)
    AutoCompleteOrdersJob.perform_now
    assert_predicate order.reload, :pending_payment?
  end

  test "runs through Orders::Transition so notifications fan out" do
    order = create_order(status: :delivered)
    order.update!(delivered_at: 3.days.ago, buyer_protection_until: 1.day.ago)

    assert_difference -> { Notification.count }, 2 do
      AutoCompleteOrdersJob.perform_now
    end
    assert_equal %w[order_completed order_completed], Notification.order(:id).last(2).map(&:kind).sort
  end

  private

  def create_order(status:)
    Order.create!(buyer: users(:one), seller: users(:two), status: status,
                  subtotal_cents: 10_000, currency: "EUR")
  end
end
