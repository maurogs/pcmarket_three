require "test_helper"

module Sell
  class SalesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @sale = create_sale(status: :pending_payment) # buyer one, seller two
    end

    # --- lookups are seller-scoped (outsiders AND the buyer 404) -----------

    test "the buyer cannot use seller routes: payment confirmation 404s for them" do
      sign_in_as users(:one) # the buyer
      assert_response :not_found, post(sell_sale_payment_confirmation_path(@sale))
      assert_predicate @sale.reload, :pending_payment?

      assert_response :not_found, post(sell_sale_shipment_path(@sale),
                                        params: { shipment: { carrier: "SEUR" } })
      assert_response :not_found, post(sell_sale_cancellation_path(@sale))
      assert_predicate @sale.reload, :pending_payment?
    end

    test "an unrelated seller gets a 404 on someone else's sale" do
      sign_in_as users(:admin)
      get sell_sale_path(@sale)
      assert_response :not_found
    end

    # --- seller transitions -------------------------------------------------

    test "seller confirms a direct payment: pending_payment becomes paid" do
      sign_in_as users(:two)
      post sell_sale_payment_confirmation_path(@sale)
      assert_redirected_to sell_sale_path(@sale)
      @sale.reload
      assert_predicate @sale, :paid?
      assert_not_nil @sale.paid_at
    end

    test "confirming payment twice is stale" do
      @sale.pay!
      paid_at = @sale.paid_at
      sign_in_as users(:two)
      post sell_sale_payment_confirmation_path(@sale)
      assert_redirected_to sell_sale_path(@sale)
      @sale.reload
      assert_predicate @sale, :paid?
      assert_equal paid_at, @sale.paid_at
    end

    test "seller ships a paid order with carrier and tracking" do
      @sale.pay!
      sign_in_as users(:two)
      post sell_sale_shipment_path(@sale),
           params: { shipment: { carrier: "SEUR", tracking_number: "TRK-9" } }
      assert_redirected_to sell_sale_path(@sale)
      @sale.reload
      assert_predicate @sale, :shipped?
      assert_equal "SEUR", @sale.carrier
      assert_equal "TRK-9", @sale.tracking_number
      assert_not_nil @sale.shipped_at
    end

    test "an unknown carrier is refused and the order stays paid" do
      @sale.pay!
      sign_in_as users(:two)
      post sell_sale_shipment_path(@sale), params: { shipment: { carrier: "FlyingCart" } }
      assert_redirected_to sell_sale_path(@sale)
      assert_predicate @sale.reload, :paid?
      assert_nil @sale.carrier
    end

    test "shipping an unpaid order is stale" do
      sign_in_as users(:two)
      post sell_sale_shipment_path(@sale), params: { shipment: { carrier: "GLS" } }
      assert_predicate @sale.reload, :pending_payment?
    end

    test "seller can cancel before shipping but not after" do
      sign_in_as users(:two)
      post sell_sale_cancellation_path(@sale)
      assert_predicate @sale.reload, :cancelled?

      other = create_sale(status: :paid)
      other.ship!(carrier: "MRW")
      post sell_sale_cancellation_path(other)
      assert_predicate other.reload, :shipped?
    end

    test "cancelling a sale restores the sold listing" do
      buyer = users(:admin)
      cart = Cart.for_user(buyer)
      cart.cart_items.create!(listing: listings(:gigabyte), quantity: 1)
      placed = Checkout::PlaceOrders.call(buyer: buyer, cart: cart,
                                          address: addresses(:one),
                                          checkout_token: SecureRandom.base58(24)).orders.first
      assert_predicate listings(:gigabyte).reload, :sold?

      sign_in_as users(:one) # the seller of gigabyte
      post sell_sale_cancellation_path(placed)
      assert_predicate placed.reload, :cancelled?
      gigabyte = listings(:gigabyte).reload
      assert_predicate gigabyte, :approved?
      assert_equal 1, gigabyte.quantity
    end

    private

    def create_sale(status:)
      Order.create!(buyer: users(:one), seller: users(:two), status: status,
                    subtotal_cents: 10_000, currency: "EUR")
    end
  end
end
