require "test_helper"

class PaymentsStripeCheckoutTest < ActiveSupport::TestCase
  setup do
    @buyer = users(:admin)
    @cart = Cart.for_user(@buyer)
    @token = SecureRandom.base58(24)
    @session_klass = Struct.new(:id, :url)
    ENV["STRIPE_SECRET_KEY"] = "sk_test_fake"
  end

  teardown do
    ENV.delete("STRIPE_SECRET_KEY")
  end

  def place_orders
    @cart.cart_items.create!(listing: listings(:as_new), quantity: 1)
    listings(:as_new).update!(shipping_price_cents: 499)
    stores(:two).update!(free_shipping_threshold_cents: 40_000)
    Checkout::PlaceOrders.call(buyer: @buyer, cart: @cart, address: addresses(:one),
                               checkout_token: @token).orders
  end

  # Minetest 6 ships no Object#stub: swap the class method for the block.
  def with_fake_stripe_create(handler)
    Stripe::Checkout::Session.singleton_class.define_method(:create) do |params|
      handler.call(params)
    end
    yield
  ensure
    Stripe::Checkout::Session.singleton_class.remove_method(:create)
  end

  test "creates a checkout session matching the order totals and links it" do
    orders = place_orders
    captured = nil

    with_fake_stripe_create(->(params) do
      captured = params
      @session_klass.new("cs_test_1", "https://checkout.stripe.com/cs_test_1")
    end) do
      result = Payments::StripeCheckout.call(
        orders: orders, buyer: @buyer,
        success_url: "https://pcm.example/orders?checkout=success",
        cancel_url: "https://pcm.example/checkout?checkout=cancelled"
      )
      assert_equal "https://checkout.stripe.com/cs_test_1", result.session.url
    end

    assert_equal "payment", captured[:mode]
    assert_equal @buyer.email_address, captured[:customer_email]
    assert_equal orders.map(&:id).join(","), captured[:metadata][:order_ids]

    expected_units = orders.sum do |order|
      order.order_items.sum(&:quantity) +
        (order.shipping_cents.positive? ? 1 : 0) +
        (order.commission_cents.positive? ? 1 : 0)
    end
    total = captured[:line_items].sum { |l| l[:price_data][:unit_amount] * l[:quantity] }
    assert_equal expected_units, captured[:line_items].sum { |l| l[:quantity] }
    assert_equal orders.sum(&:total_cents), total

    orders.each do |order|
      assert_equal "cs_test_1", order.reload.payment_reference
    end
  end
end
