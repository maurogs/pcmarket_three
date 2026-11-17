module Api
  module V1
    # POST /api/v1/orders/:order_id/completion — buyer closes a delivered
    # order (delivered → completed; AutoCompleteOrdersJob does the same once
    # the protection window lapses). Buyers only, stale states 409.
    class CompletionsController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        result = Orders::Transition.call(order: @order, action: "completed")

        if result.order
          @order = result.order
          @message = t("api.order_transitions.completed")
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
