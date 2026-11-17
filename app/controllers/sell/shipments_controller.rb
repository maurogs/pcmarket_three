module Sell
  # POST /sell/sales/:sale_id/shipment — the seller ships a paid order:
  # paid→shipped with a carrier (Order::CARRIERS) and an optional
  # tracking number. Sellers only (current_user.sales lookup).
  class ShipmentsController < BaseController
    def create
      sale = current_user.sales.find(params[:sale_id])
      carrier = params.dig(:shipment, :carrier).to_s

      unless Order::CARRIERS.include?(carrier)
        return redirect_to sell_sale_path(sale), alert: t(".unknown_carrier")
      end

      result = Orders::Transition.call(
        order: sale, action: "shipped",
        carrier: carrier,
        tracking_number: params.dig(:shipment, :tracking_number).to_s.presence
      )

      if result.order
        redirect_to sell_sale_path(sale), notice: t(".shipped")
      else
        redirect_to sell_sale_path(sale), alert: t("orders.transition.stale")
      end
    end
  end
end
