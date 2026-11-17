# "My orders" for the signed-in buyer. Every lookup goes through
# current_user.orders, so other people's orders 404 (never 403).
class OrdersController < ApplicationController
  PER_PAGE = 10

  def index
    @pagy, @orders = pagy(current_user.orders.recent.includes(:order_items), limit: PER_PAGE)
  end

  def show
    @order = current_user.orders.includes(order_items: :listing).find(params[:id])
  end
end
