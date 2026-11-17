module Api
  module V1
    # POST /api/v1/orders/:order_id/shipment — seller ships a paid order
    # (paid → shipped), carrier from the Order::CARRIERS whitelist plus an
    # optional tracking number. Sellers only (current_user.sales lookup),
    # unknown carriers 422, stale states 409 — same rules as
    # Sell::ShipmentsController.
    class ShipmentsController < BaseController
      before_action :verify_user!
      before_action :set_order

      def create
        carrier = params[:carrier].to_s
        if carrier.present? && !Order::CARRIERS.include?(carrier)
          return render_error(:unprocessable_entity, :unknown_carrier,
                              message: t("api.shipments.errors.unknown_carrier"))
        end

        result = Orders::Transition.call(order: @order, action: "shipped",
                                         carrier: carrier.presence,
                                         tracking_number: params[:tracking_number].to_s.presence)

        if result.order
          @order = result.order
          @message = t("api.order_transitions.shipped")
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
