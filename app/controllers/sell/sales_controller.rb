module Sell
  # Updates (3b) were read-only for the seller; fulfilment actions
  # (payment confirmation, shipment, cancellation) landed with the
  # checkout phase — see the nested resources in config/routes.rb.
  class SalesController < BaseController
    PER_PAGE = 20

    def index
      @pagy, @sales = pagy(current_user.sales.recent.includes(:order_items), limit: PER_PAGE)
    end

    def show
      @sale = current_user.sales.includes(order_items: :listing).find(params[:id])
    end
  end
end
