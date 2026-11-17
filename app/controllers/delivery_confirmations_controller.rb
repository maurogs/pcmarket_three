# POST /orders/:order_id/delivery_confirmation — the buyer says the parcel
# arrived. paid→...→shipped→delivered; the buyer-protection window starts
# here (Order#mark_delivered!). Buyers only: the lookup runs through
# current_user.orders, so the seller 404s on this route.
class DeliveryConfirmationsController < ApplicationController
  def create
    order = current_user.orders.find(params[:order_id])
    result = Orders::Transition.call(order: order, action: "delivered")

    if result.order
      redirect_to order_path(order), notice: t(".confirmed")
    else
      redirect_to order_path(order), alert: t("orders.transition.stale")
    end
  end
end
