module Sell
  # Orders where the signed-in user is the seller. Read-only for now:
  # shipping/fulfilment actions land with the checkout phase. Lookups go
  # through current_user.sales, so another seller's order 404s.
  class SalesController < BaseController
    PER_PAGE = 20

    def index
      @pagy, @sales = pagy(current_user.sales.recent.includes(:order_items), limit: PER_PAGE)
    end

    def show
      @sale = current_user.sales.find(params[:id])
    end
  end
end
