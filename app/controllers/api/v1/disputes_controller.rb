module Api
  module V1
    # POST /api/v1/orders/:order_id/dispute — open a dispute (delivered →
    # disputed, inside the buyer-protection window; Order#open_dispute! and
    # Orders::Transition own both the guard and the admin notifications).
    # Either party; outsiders 404; stale/closed-window states 409.
    class DisputesController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        result = Orders::Transition.call(order: @order, action: "disputed")

        if result.order
          @order = result.order
          @message = t("api.order_transitions.disputed")
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
