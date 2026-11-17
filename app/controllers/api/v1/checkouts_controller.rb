module Api
  module V1
    # POST /api/v1/checkout — places the cart. The whole ordering engine
    # is Checkout::PlaceOrders (row locks, replay-safe checkout_token,
    # recomputed totals); this controller only maps JSON params onto it and
    # chooses the payment mode exactly like the web (Stripe Checkout when
    # the server is configured for it, direct mode otherwise). In direct
    # mode Checkout::DirectPayment seeds each buyer↔seller thread with the
    # order number, and the seller later confirms payment through the
    # payment_confirmation resource.
    class CheckoutsController < BaseController
      before_action :verify_user!

      def create
        token = params[:checkout_token].presence || SecureRandom.base58(24)
        address = current_user.addresses.find_by(id: params[:address_id])
        stripe = stripe_mode?

        result = Checkout::PlaceOrders.call(
          buyer: current_user, cart: Cart.for_user(current_user), address: address,
          checkout_token: token, pickup_seller_ids: [],
          payment_provider: stripe ? "stripe" : "direct"
        )

        if result.error
          return render_error(:unprocessable_entity, result.error,
                              message: t("api.checkouts.errors.#{result.error}"))
        end

        # 201 per the OpenAPI contract; the payload is a plain hash, so it has
        # to be handed to render as json: — a bare hash is read as render options.
        payload = stripe ? stripe_response(token, result.orders) : direct_response(token, result.orders)
        render json: payload, status: :created
      end

      private

        # Same gate as CheckoutsController#stripe_mode? — the flag alone is
        # not enough, the secret key has to be configured server-side.
        def stripe_mode?
          Flipper.enabled?(:stripe_checkout) && ENV["STRIPE_SECRET_KEY"].present?
        end

        def stripe_response(token, orders)
          stripe = Payments::StripeCheckout.call(
            orders: orders, buyer: current_user,
            success_url: orders_url(checkout: "success"),
            cancel_url: checkout_url(checkout: "cancelled")
          )

          {
            checkout_token: token, mode: "stripe", order_ids: orders.map(&:id),
            conversation_ids: [], redirect_url: stripe.session.url,
            message: t("api.checkouts.placed")
          }
        end

        def direct_response(token, orders)
          Checkout::DirectPayment.call(orders: orders, buyer: current_user)

          {
            checkout_token: token, mode: "direct", order_ids: orders.map(&:id),
            conversation_ids: thread_ids_for(orders), redirect_url: nil,
            message: t("api.checkouts.placed")
          }
        end

        # DirectPayment seeds one thread per order from the order's first
        # item listing — same lookup the service itself makes.
        def thread_ids_for(orders)
          orders.filter_map do |order|
            listing = order.order_items.where.not(listing_id: nil).first&.listing
            next if listing.nil?

            Conversation.find_by(listing_id: listing.id, buyer_id: current_user.id,
                                 seller_id: order.seller_id)&.id
          end
        end
    end
  end
end
