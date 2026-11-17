module Sell
  # POST /sell/sales/:sale_id/cancellation — seller-side cancel: allowed
  # up to (but not including) shipment, i.e. while pending_payment or
  # paid (Order#cancel! accepts both; shipped orders are past the point).
  # Listings go back on sale. Sellers only (current_user.sales lookup).
  class CancellationsController < BaseController
    def create
      sale = current_user.sales.find(params[:sale_id])
      result = Orders::Transition.call(order: sale, action: "cancelled")

      if result.order
        redirect_to sell_sale_path(sale), notice: t(".cancelled")
      else
        redirect_to sell_sale_path(sale), alert: t("orders.transition.stale")
      end
    end
  end
end
