# POST /orders/:order_id/completion — buyer closes the deal after
# delivery (delivered→completed). AutoCompleteOrdersJob performs the same
# transition once the protection window lapses. Buyers only.
class CompletionsController < ApplicationController
  def create
    order = current_user.orders.find(params[:order_id])
    result = Orders::Transition.call(order: order, action: "completed")

    if result.order
      redirect_to order_path(order), notice: t(".completed")
    else
      redirect_to order_path(order), alert: t("orders.transition.stale")
    end
  end
end
