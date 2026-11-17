module Api
  module V1
    # POST /api/v1/orders/:order_id/payment_confirmation — direct payment
    # mode: the SELLER confirms the money arrived (pending_payment → paid).
    # Buyer-role callers 404, exactly like the web (lookup through
    # current_user.sales); a stale state 409s.
    class PaymentConfirmationsController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        result = Orders::Transition.call(order: @order, action: "paid")

        if result.order
          @order = result.order
          @message = t("api.order_transitions.confirmed")
          render :create
        else
          render_error(:conflict, :stale_transition)
        end
      end

      private

        def set_order
          @order = current_user.sales.find(params[:order_id])
        end
    end
  end
end
