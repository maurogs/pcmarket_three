module Api
  module V1
    # POST /api/v1/orders/:order_id/delivery_confirmation — the BUYER says
    # the parcel arrived (shipped → delivered, protection window opens).
    # Buyers only through current_user.orders, sellers 404.
    class DeliveryConfirmationsController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        result = Orders::Transition.call(order: @order, action: "delivered")

        if result.order
          @order = result.order
          @message = t("api.order_transitions.delivered")
          render :create
        else
          render_error(:conflict, :stale_transition)
        end
      end

      private

        def set_order
          @order = current_user.orders.find(params[:order_id])
        end
    end
  end
end
