# POST /orders/:order_id/cancellation — buyer-side cancel: allowed while
# the order is still pending_payment (once payment is arranged the seller
# has the choice — see Sell::CancellationsController). Order#cancel!
# restores the listings; Orders::Transition notifies both parties.
class CancellationsController < ApplicationController
  def create
    order = current_user.orders.find(params[:order_id])
    result = Orders::Transition.call(order: order, action: "cancelled")

    if result.order
      redirect_to order_path(order), notice: t(".cancelled")
    else
      redirect_to order_path(order), alert: t("orders.transition.stale")
    end
  end
end
