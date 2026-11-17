module Api
  module V1
    # POST /api/v1/orders/:order_id/cancellation — either party may cancel
    # while the order is cancellable (Order#cancel! restricts to
    # pending_payment/paid and puts every listing back on sale). Anyone who
    # is neither buyer nor seller 404s.
    class CancellationsController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        result = Orders::Transition.call(order: @order, action: "cancelled")

        if result.order
          @order = result.order
          @message = t("api.order_transitions.cancelled")
          render :create
        else
          render_error(:conflict, :stale_transition)
        end
      end

      private

        def set_order
          @order = Order.where("orders.buyer_id = :me OR orders.seller_id = :me",
                               me: current_user.id).find(params[:order_id])
        end
    end
  end
end
