module Sell
  # POST /sell/sales/:sale_id/payment_confirmation — direct (off-platform)
  # payment mode: the seller confirms they actually received the money,
  # which moves pending_payment→paid. Sellers only: the lookup runs
  # through current_user.sales, buyers 404 on this route.
  class PaymentConfirmationsController < BaseController
    def create
      sale = current_user.sales.find(params[:sale_id])
      result = Orders::Transition.call(order: sale, action: "paid")

      if result.order
        redirect_to sell_sale_path(sale), notice: t(".confirmed")
      else
        redirect_to sell_sale_path(sale), alert: t("orders.transition.stale")
      end
    end
  end
end
