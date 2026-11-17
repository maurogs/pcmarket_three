require "test_helper"

class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @order = create_order(status: :pending_payment)
  end

  # --- lookups are buyer-scoped (outsiders AND the seller 404) --------------

  test "buyer sees their orders" do
    sign_in_as users(:one)
    get orders_path
    assert_response :success
    get order_path(@order)
    assert_response :success
  end

  test "a stranger gets a 404 on someone else's order" do
    sign_in_as users(:admin)
    get order_path(@order)
    assert_response :not_found
  end

  test "the seller cannot use buyer routes: confirming delivery 404s for them" do
    @order.pay!
    @order.ship!(carrier: "Correos")

    sign_in_as users(:two) # the seller
    assert_response :not_found, post(order_delivery_confirmation_path(@order))
    assert_predicate @order.reload, :shipped?

    assert_response :not_found, post(order_completion_path(@order))
    assert_response :not_found, post(order_cancellation_path(@order))
  end

  test "the buyer cannot ship: there is no buyer-side shipment route (seller-only, and the seller route 404s)" do
    @order.pay!
    sign_in_as users(:one) # buyer
    assert_response :not_found, post(sell_sale_shipment_path(@order))
    assert_predicate @order.reload, :paid?
  end

  # --- buyer-side transitions ----------------------------------------------

  test "buyer cancels while pending_payment and listings go back on sale" do
    buyer = users(:admin)
    cart = Cart.for_user(buyer)
    listings(:as_new).update!(quantity: 2)
    cart.cart_items.create!(listing: listings(:as_new), quantity: 2)
    placed = Checkout::PlaceOrders.call(buyer: buyer, cart: cart,
                                        address: addresses(:two),
                                        checkout_token: SecureRandom.base58(24)).orders.first

    sign_in_as buyer
    post order_cancellation_path(placed)
    assert_redirected_to order_path(placed)
    assert_predicate placed.reload, :cancelled?
    assert_equal 2, listings(:as_new).reload.quantity # the two units come back
  end

  test "buyer cannot cancel a shipped order" do
    @order.pay!
    @order.ship!(carrier: "SEUR")
    sign_in_as users(:one)

    post order_cancellation_path(@order)
    assert_redirected_to order_path(@order)
    assert_predicate @order.reload, :shipped?
  end

  test "buyer confirms delivery, then completes" do
    @order.pay!
    @order.ship!(carrier: "MRW")

    sign_in_as users(:one)
    post order_delivery_confirmation_path(@order)
    assert_redirected_to order_path(@order)
    assert_predicate @order.reload, :delivered?
    assert_not_nil @order.buyer_protection_until

    post order_completion_path(@order)
    assert_predicate @order.reload, :completed?
  end

  test "confirming delivery on a paid (not shipped) order is stale" do
    @order.pay!
    sign_in_as users(:one)
    post order_delivery_confirmation_path(@order)
    assert_predicate @order.reload, :paid?
  end

  test "dispute inside the protection window works, outside it is refused" do
    @order.pay!
    @order.ship!(carrier: "DHL")
    @order.mark_delivered!

    sign_in_as users(:one)
    post order_dispute_path(@order)
    assert_predicate @order.reload, :disputed?

    other = create_order(status: :delivered)
    other.update!(delivered_at: 10.days.ago, buyer_protection_until: 1.day.ago)
    post order_dispute_path(other)
    assert_predicate other.reload, :delivered?
  end

  # --- review once per completed order --------------------------------------

  test "a completed order can be reviewed exactly once" do
    completed = create_order(status: :completed)

    sign_in_as users(:one)
    get new_order_review_path(completed)
    assert_response :success

    assert_difference -> { Review.count }, 1 do
      post order_review_path(completed), params: { review: { rating: 5, body: "Great" } }
    end

    post order_review_path(completed), params: { review: { rating: 1, body: "Again?" } }
    assert_equal 1, Review.count
    assert_redirected_to order_path(completed)
  end

  test "a not-completed order is not reviewable" do
    sign_in_as users(:one)
    get new_order_review_path(@order)
    assert_redirected_to order_path(@order)
    assert_no_difference -> { Review.count } do
      post order_review_path(@order), params: { review: { rating: 5 } }
    end
  end

  private

  def create_order(status:)
    Order.create!(buyer: users(:one), seller: users(:two), status: status,
                  subtotal_cents: 10_000, currency: "EUR")
  end
end
