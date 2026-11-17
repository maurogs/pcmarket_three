# POST /orders/:order_id/dispute — buyer raises a problem after delivery,
# while the buyer-protection window is open (Order#open_dispute! guards
# the window; admins get a notification — see Orders::Transition).
class DisputesController < ApplicationController
  def create
    order = current_user.orders.find(params[:order_id])
    result = Orders::Transition.call(order: order, action: "disputed")

    if result.order
      redirect_to order_path(order), notice: t(".opened")
    else
      redirect_to order_path(order), alert: t("orders.transition.stale")
    end
  end
end
