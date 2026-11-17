module Payments
  # Stripe Checkout Session for pending_payment orders (only reached when
  # Flipper :stripe_checkout is on AND STRIPE_SECRET_KEY is set — see
  # CheckoutsController). One line item per order item, plus shipping and
  # commission lines so the session total matches the order totals; the
  # order ids ride along in the session metadata and the session id is
  # stored on the orders for the webhook to find.
  class StripeCheckout
    Result = Struct.new(:session, keyword_init: true)

    def self.call(orders:, buyer:, success_url:, cancel_url:)
      new(orders: orders, buyer: buyer, success_url: success_url, cancel_url: cancel_url).call
    end

    def initialize(orders:, buyer:, success_url:, cancel_url:)
      @orders = orders
      @buyer = buyer
      @success_url = success_url
      @cancel_url = cancel_url
    end

    def call
      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
      stripe_session = Stripe::Checkout::Session.create(
        mode: "payment",
        currency: "eur",
        customer_email: buyer.email_address,
        line_items: line_items,
        metadata: { order_ids: orders.map(&:id).join(",") },
        success_url: success_url,
        cancel_url: cancel_url
      )

      Order.where(id: orders.map(&:id)).update_all(payment_reference: stripe_session.id)
      Result.new(session: stripe_session)
    end

    private

    attr_reader :orders, :buyer, :success_url, :cancel_url

    def line_items
      orders.flat_map do |order|
        items = order.order_items.map do |item|
          line(item.title, item.price_cents, item.quantity)
        end
        items << line(I18n.t("payments.stripe.shipping_line"), order.shipping_cents, 1) if order.shipping_cents.positive?
        items << line(I18n.t("payments.stripe.commission_line"), order.commission_cents, 1) if order.commission_cents.positive?
        items
      end
    end

    def line(name, unit_amount, quantity)
      {
        quantity: quantity,
        price_data: {
          currency: "eur",
          unit_amount: unit_amount,
          product_data: { name: name }
        }
      }
    end
  end
end
