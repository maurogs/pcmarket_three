module Payments
  # Applies a verified Stripe webhook event to the orders it references.
  # checkout.session.completed  → mark pending_payment orders paid.
  # checkout.session.expired    → cancel them and put the listings back on
  # sale (Orders::Transition → Order#cancel! → restore_listings!).
  class HandleWebhook
    def self.call(event)
      new(event).call
    end

    def initialize(event)
      @event = event
    end

    def call
      case event.type
      when "checkout.session.completed" then mark_paid
      when "checkout.session.expired" then expire_session
      end
    end

    private

    attr_reader :event

    def stripe_session
      event.data.object
    end

    def linked_orders
      metadata = stripe_session["metadata"]
      id_list = (metadata && metadata["order_ids"]).to_s.split(",")
      ids = id_list.filter_map { |id| id.match?(/\A\d+\z/) ? id.to_i : nil }
      Order.where(id: ids).or(Order.where(payment_reference: stripe_session.id))
    end

    def mark_paid
      linked_orders.where(status: :pending_payment).find_each do |order|
        Orders::Transition.call(order: order, action: "paid")
      end
    end

    def expire_session
      linked_orders.where(status: :pending_payment).find_each do |order|
        Orders::Transition.call(order: order, action: "cancelled")
      end
    end
  end
end
