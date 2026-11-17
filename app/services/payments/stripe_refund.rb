module Payments
  # Refund of a Stripe-processed order (admin dispute resolutions). The
  # order's `payment_reference` is the Checkout Session id stored by
  # Payments::StripeCheckout; Stripe refunds hang off the session's payment
  # intent. Only reached when the reference is present — manual (direct)
  # payments are marked refunded without calling out.
  class StripeRefund
    def self.call(order:, amount_cents: nil)
      new(order: order, amount_cents: amount_cents).call
    end

    def initialize(order:, amount_cents: nil)
      @order = order
      @amount_cents = amount_cents
    end

    def call
      Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
      session = Stripe::Checkout::Session.retrieve(order.payment_reference)
      Stripe::Refund.create(
        payment_intent: session.payment_intent,
        amount: amount_cents || order.total_cents
      )
    end

    private

    attr_reader :order, :amount_cents
  end
end
